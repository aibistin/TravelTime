# ABSTRACT: Calculate fixed travel times for Commercial Moving Truck
package TravelTime;
use Modern::Perl qw/2012/;
use Dancer2;

our $VERSION = '0.1';

#----My HTML::Formhandler Module
use Mover::Form::Travel::Matrix;
use Template;
use Data::Dump qw/dump/;
use Carp qw/croak/;
use Try::Tiny;

#------ My Interface with Google Travel Matrix
use Google::Travel::Matrix 0.02;

#------ Get the Logs from Google::Travel::Matrix
use Log::Any::Adapter qw/Stdout/;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

#------ Globals
my $TRUE  = 1;
my $FALSE = 0;

my $tm_form;
my $template = q//;

my $form_page             = q(/);
my $results_page          = q(/travel_time);
my $error_page_template   = q/error.tt/;
my $travel_time_template  = q/travel_time.tt/;
my $results_page_template = q/travel_results.tt/;

my %my_errors;

#------ Google Matrix Response status codes
my $VALID_REQ               = q/OK/;
my $INVALID_REQ             = q/INVALID_REQUEST/;
my $MAX_ELEMENTS_EXCEEDED   = q/MAX_ELEMENTS_EXCEEDED/;
my $MAX_DIMENSIONS_EXCEEDED = q/MAX_DIMENSIONS_EXCEEDED/;
my $MAX_QUERY_LIMIT         = q/MAX_QUERY_LIMIT/;
my $REQ_DENIED              = q/REQUEST_DENIED/;
my $UNKNOWN_ERROR           = q/UNKNOWN_ERROR/;

my %google_status_messages = (
    $VALID_REQ   => q/Google is happy!/,
    $INVALID_REQ => q/Google said that this request is invalid. Go figure!/,
    $MAX_ELEMENTS_EXCEEDED =>
      q/Google said that you have too many addresses in your query!/,
    $MAX_DIMENSIONS_EXCEEDED =>
q/Google thinks that the request URL is much too long for it to handle! Try shorter addresses./,
    $MAX_QUERY_LIMIT =>
q/Google said that you have asked enough for one day. Please come back again tomorrow!/,
    $REQ_DENIED =>
      q/Google denied your request. It may not like you for some reason./,
    $UNKNOWN_ERROR => q/Google is not happy, but it wont tell us why!/,

);

#------ Google Matrix Element status codes
my $OK           = q/OK/;
my $NOT_FOUND    = q/NOT_FOUND/;
my $ZERO_RESULTS = q/ZERO_RESULTS/;

#-------------------------------------------------------------------------------
#  GET
#-------------------------------------------------------------------------------
get $form_page => sub {
    debug 'Got to render page.';

    my $error_page;
    try {
        $tm_form = Mover::Form::Travel::Matrix->new( fif_from_value => 1 );
    }
    catch {
        error 'Got error with form : ' . $_;
        $error_page = process_error(
            {
                Error      => 'The Travel Matrix Form is really messed up!',
                Form_error => substr( $_, 0, 400 ),
            }
        );
    };

    return $error_page unless $tm_form;

    my $init_object = {
        addresses => [
            config->{Address}{origins}{1},
            config->{Address}{destinations}{1},
            config->{Address}{destinations}{2},
        ],
    };

    #------ Create the initial address(s) and add the final address field
    $tm_form->process( init_object => $init_object );
    $tm_form->field('addresses')->add_extra(1);

    template $travel_time_template,
      {
        title               => config->{Display}{tm_title},
        travel_time_heading => config->{Display}{tm_heading_1},
        tm_form             => $tm_form,
        info_message        => config->{Display}{intro_message},
      };

};

#-------------------------------------------------------------------------------
#  POST
#-------------------------------------------------------------------------------
post $results_page => sub {
    return redirect $form_page unless $tm_form;

    $tm_form->process( params => {params} );

    #    debug 'Is form validated ? ' . $tm_form->validated;
    #    debug 'Is form valid ? ' . $tm_form->is_valid;
    #    debug 'Form errors ? ' . $tm_form->errors;
    #    debug 'Fields with errors ? ' . $tm_form->error_fields;
    #    debug 'Form params ? ' . dump $tm_form->params;
    #    debug 'Form vaules ? ' . dump $tm_form->value;
    #
    #    debug 'Form Fields : ' . join "\nField: ", $tm_form->sorted_fields;
    #    debug 'Form Address SubFields : ' . join "\nSub Field: ",
    #      $tm_form->field('addresses')->sorted_fields;

    my %template_vars = (
        title               => config->{Display}{tm_title},
        travel_time_heading => config->{Display}{tm_heading_2},
        tm_form             => $tm_form,
        travel_time_start   => $form_page,
    );

    debug 'Returned form rc is: '
      . ( $tm_form->is_valid // 'Nothing returned!' );
    my $mover_travel_results;

    if ( $tm_form->validated && $tm_form->is_valid ) {
        debug 'Form is fully valid!';
        $mover_travel_results = get_all_itinerary_data();

        #------ Check for processing errors.
        if ( keys %my_errors ) {
            %template_vars = (
                %template_vars,
                info_message => 'Please check that the addresses(s) are valid.',
                error_message     => config->{Display}{error_message},
                my_errors         => \%my_errors,
                travel_time_start => $form_page,
            );
            $template = $travel_time_template;
        }
        else {

            #------ Success
            debug 'Final travel results are : ' . dump $mover_travel_results;
            %template_vars = (
                %template_vars,
                result_heading => config->{Display}{result_heading},
                success_message =>
                  ( config->{Display}{success_message} || 'Thanks Google!' ),
                results_table_heading =>
                  config->{Display}{results_table_heading},
                mover_travel_results => $mover_travel_results,
                travel_time_start    => $form_page,
            );
            $template = $results_page_template;
        }
        template $template, \%template_vars;
    }
    else {
        debug 'Form has errors : ' . dump $tm_form->errors;
        $template = $travel_time_template;

        debug 'The form error message is: ' . $tm_form->error_message;
        %template_vars = (
            %template_vars, 
            info_message  => 'Please check that the addresses(s) are valid.',
            error_message => config->{Display}{error_message},
        );
        template $template, \%template_vars;
    }

};

#-------------------------------------------------------------------------------
#   Wrong route
#-------------------------------------------------------------------------------
any qr{.*} => sub {
    process_error(
        {
            Error              => 'You took a wrong turn. Please get a map!',
            the_incorrect_path => request->path,
        }
    );
};

#-------------------------------------------------------------------------------
#  Render Error Page
#  Pass a message and a URL to return to.
#-------------------------------------------------------------------------------
sub process_error {
    my $error_messages = shift;
    error "Got these errors : \n" . dump $error_messages;
    return template $error_page_template,
      {
        error_messages    => $error_messages,
        travel_time_start => $form_page,
      };
}

#-------------------------------------------------------------------------------
#  Call the Google
#-------------------------------------------------------------------------------

=head2 get_google_itinerary_data
   Call the google matrix with the user supplied addresses.
   Return an array containing Google data for each address combination.
=cut

sub get_google_itinerary_data {
    my $itinerary_arr = create_itinerary(params);
    my $Gm            = get_google_travel_matrix();
    return get_google_matrix_data( $Gm, $itinerary_arr ) if $Gm;
}

#-------------------------------------------------------------------------------
#  Create an itinerary of addresses.
#-------------------------------------------------------------------------------

=head2 create_itinerary
  Create an array of each address in the order of the itinerary.
  The address will be in HashRef format.
  For simplicity only the first address will be treated as an "origin"
  address. All other addresses will be treated as destination addresses.
=cut

sub create_itinerary {
    my $form = shift;
    my @address_array;

    #------ Get The Addresses
    foreach my $address ( $tm_form->field('addresses')->fields ) {
        my %address_hash;
        foreach my $field ( $address->fields ) {

 #            debug 'Form With Extras Address SubFields Name : ' . $field->name;
 #            debug 'Form With Extras Address SubFields Value: '
 #              . ( $field->value || '<EMPTY>' );
            $address_hash{ $field->name } = $field->value;
        }
        push @address_array, \%address_hash;
    }

    debug 'The itinerary passed to Google is : ' . dump(@address_array);
    return \@address_array;
}

=head2 get_google_travel_matrix
 Create  a Google::Travel::Matrix object.
 This is our interface with the Google Travel Matrix API.
 Returns a Google::Travel::Matrix object.
=cut

sub get_google_travel_matrix {
    my $GoogMx;
    try {
        $GoogMx = Google::Travel::Matrix->new( config->{Google}{Params}, );
    }
    catch {
        $my_errors{goog_matrix} = "Failed to connect to Google!</br> Please try
        again.";
        error 'Unable to create Google::Travel::Marix: ' . $_;
    };
    return $GoogMx;
}

=head2 get_google_matrix_data
  Get distances from the Google matrix.
  Pass the Google::Travel::Matrix object and an array containing
  the Origination address as well as the destination address.
  For simplicity only the first address will be treated as an "origin"
  address. All other addresses will be treated as destination addresses.

Returns an array of HashRefs....
[
    {
        origin_address         => $origin_address,
        destination_address    => $destination_address,
        element_status         => $element_status,
        element_duration_text  => $element_duration_text,
        element_duration_value => $element_duration_value,
        element_distance_text  => $element_distance_text,
        #------ This distance is ALWAYS in Meters.
        element_distance_value => $element_distance_value,
        distance_in_miles      => sub { calculate distance in miles },
    },
    {},
]
=cut

sub get_google_matrix_data {
    my $GoogTrMatrix  = shift;
    my $itinerary_arr = shift;
    my ( $matrix_data, @results_arr, @elements );
    try {

#------ Treat the first itinerary address as the origin #       this is the only way that the first 20 miles rule
#       works for now.
        $GoogTrMatrix->origins( shift @$itinerary_arr );
        $GoogTrMatrix->destinations($itinerary_arr);
        $matrix_data = $GoogTrMatrix->get_google_matrix_data_as_scalar_ref();
    }
    catch {
        error 'Got an error with the address(s): ' . $_;
        $my_errors{goog_matrix_addresses} = "Got an error with the addresses. ";
    };
    my $google_status = $GoogTrMatrix->get_matrix_status_message($matrix_data);
    if ( $google_status and $google_status eq $VALID_REQ ) {
        @elements = @{ $GoogTrMatrix->get_all_elements($matrix_data) };

    }
    else {
        error 'Google Distance Matrix returned a bad status message: '
          . ( $google_status // q// );
        $my_errors{goog_matrix_status} = $google_status |= q/ABBYNORMAL/;
        $my_errors{goog_matrix_message} =
          $google_status_messages{$google_status} // 'Google was so angry, it
          didnt even return a proper status code!!!';
        return;

    }
    foreach my $itinerary (@elements) {

        #------ Google gives the distance value in meters. It gives a text
        #       value in metric or imperial measurement, but the meters value
        #       is consistant.

        push @results_arr, {
            origin_address         => $itinerary->{origin_address},
            destination_address    => $itinerary->{destination_address},
            element_status         => $itinerary->{element_status},
            element_duration_text  => $itinerary->{element_duration_text},
            element_duration_value => $itinerary->{element_duration_value},
            element_distance_text  => $itinerary->{element_distance_text},

            #------ This distance is ALWAYS in Meters.
            element_distance_value => $itinerary->{element_distance_value},
            distance_in_miles      => convert_from_meters_to_miles(
                $itinerary->{element_distance_value}
            ),
        };
    }

    return \@results_arr;
}

=head2 get_all_itinerary_data
  Get the iteinerary data from Google::Travel::Matrix
  Get Mover Travel Time For each "From" "To" address combination.
  Add it to each HashRef of Google::Travel::Matrix results.
  Return an array with HashRefs of all itinerary data for each "To"/"From"
  address element.
  
  @all_itinerary_data =
  [
    (
    %google_matrix_result,
    mover_travel_time_minutes => sub{ #calculate mover travel time},
    mover_travel_time => {
            hours         => int( $minutes / 60 ),
            minutes       => $minutes % 60,
            hours_minutes => $minutes / 60,
        },
    ), 
    (
    %google_matrix_result,
    mover_travel_time_minutes => sub{},
    mover_travel_time => {},
    ), 
    ..... 
  ]

=cut

sub get_all_itinerary_data {
    my @goog_matrix_results_with_tt;
    my $total_mover_travel_time_minutes;

    #------- Get the array of Google Matrix Element Results
    #        Add a new key/value to the Element results HashRef
    #        This key/value pair will be
    #        'mover_travel_time' => $mover_travel_time
    #
    my $google_itinerary_data = get_google_itinerary_data();
    return
      unless ( $google_itinerary_data
        and ref($google_itinerary_data) eq 'ARRAY' );
    for my $goog_mx_el_result (@$google_itinerary_data) {
        if ( $goog_mx_el_result->{element_status} eq $OK ) {

            #------ Get a grand total travel time in minutes.
            $total_mover_travel_time_minutes += my $mover_travel_time_minutes =
              convert_miles_to_travel_time(
                $goog_mx_el_result->{distance_in_miles} );
            %$goog_mx_el_result = (
                %$goog_mx_el_result,
                mover_travel_time_minutes => $mover_travel_time_minutes,
                mover_travel_time =>
                  convert_minutes_to_hours_minutes($mover_travel_time_minutes),
            );

        }
        else {
            %$goog_mx_el_result = (
                %$goog_mx_el_result,
                mover_travel_time_minutes => 0,
                mover_travel_time         => 0,
            );
        }

        push @goog_matrix_results_with_tt, $goog_mx_el_result;
    }
    return \@goog_matrix_results_with_tt;
}

#-------------------------------------------------------------------------------
#  Convert Miles To Truck Travel Time
#  Returns the time in minutes;
#-------------------------------------------------------------------------------

=head2 convert_miles_to_travel_time
 Uses this method:
    The first 20 miles is 60 minutes.
    Each 10 miles after that is 15 mins
    Note:  
        15 minutes is the smallest time unit.
        The given milage is converted to an integer, therefore removing any fractions.
        This integer milage is rounded up to next highest 10 miles.

=cut

sub convert_miles_to_travel_time {

    #------ Not concerned with faction of mile.
    my $distance = abs(shift);
    return 60 if ( $distance <= 20 );
    my $time_minutes = 60;
    $distance -= 20;
    my $mod;
    my $dist_rounded =
      ( ( $mod = $distance % 10 ) == 0 )
      ? int $distance
      : int( $distance += ( 10 - $mod ) );

    return $time_minutes += ( $dist_rounded / 10 ) * 15;
}

#-------------------------------------------------------------------------------
#  Convert minutes to hours and minutes
#  Returns a HashRef with hours, minutes and hours with hour fractions;
#-------------------------------------------------------------------------------
sub convert_minutes_to_hours_minutes {
    my $minutes = shift;
    return {
        hours         => int( $minutes / 60 ),
        minutes       => $minutes % 60,
        hours_minutes => $minutes / 60,
    };
}

#-------------------------------------------------------------------------------
#  Convert meters to miles.
#-------------------------------------------------------------------------------
sub convert_from_meters_to_miles {
    my $miles = $_[0] * 0.000621371;
    return sprintf( "%.1f", $miles );
}

sub convert_from_miles_to_meters {
    return $_[0] * 1609.34;
}

#-------------------------------------------------------------------------------
true;

__END__

=head1 NAME
 TravelTime -  Calculate Truck Travel Times
=cut

=head1 VERSION
Version 0.01
=cut

=head1 SYNOPSIS
                                           



=cut

=head1 DESCRIPTION
 This application allows a user to calculate the standard travel time between
 two points based on the New York City Department of Transportation guidelines
 for Household Goods Carriers.
=cut

=head1 SEE ALSO

=over

=item *
 L<Dancer>

=item *
 L<Template::Toolkit>
=item *

 L<Email::Sender>

=back

=head1 AUTHOR

Austin Kenny, C<< <aibistin.cionnaith at gmail.com> >>


=head1 ACKNOWLEDGEMENTS
       All CPAN Contributers
=cut

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Austin Kenny.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

=head2 The Results Array
    {
        origin_address         => $origin_address,
        destination_address    => $destination_address,
        element_status         => $element_status,
        element_duration_text  => $element_duration_text,
        element_duration_value => $element_duration_value,
        element_distance_text  => $element_distance_text,   # imperial or metric
        element_distance_value => $element_distance_value,  # Given in meters
        distance_in_miles =>
          sub { c_convert_from_meters_to_miles($element_distance_value) },
        mover_travel_time_minutes =>
          sub { convert_miles_to_travel_time($distance_in_miles) },
        mover_travel_time => {
            hours         => int( $minutes / 60 ),
            minutes       => $minutes % 60,
            hours_minutes => $minutes / 60,
        },
    }
=cut
