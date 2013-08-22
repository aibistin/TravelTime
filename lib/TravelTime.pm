# ABSTRACT: Calculate fixed travel times for Commercial Moving Truck
package TravelTime;
use Modern::Perl;
use autodie;
use Dancer2;
use Dancer2::Plugin::Ajax;
our $VERSION = '0.2';
use Log::Any::Adapter qw/Stdout/;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

#----My HTML::Formhandler Module
use Mover::Form::Travel::Matrix;

#------ My Interface with Google Travel Matrix
use Google::Travel::Matrix;
use Template;
use Data::Dump qw/dump/;
use Carp qw/croak/;
use Try::Tiny;
use Regexp::Common qw /zip/;

#------ My DBI stuff
#  Prepare_select_city_state_cty_ord
use MyDatabase qw/
  db_handle
  select_city_state_cty
  select_nyc_zip
  get_state_code_from_name
  get_state_name_from_code
  /;

#------ Globals
my $TRUE  = 1;
my $FALSE = 0;
my $DBH;

my $ERROR_PAGE_TEMPLATE        = q/error.tt/;
my $TRAVEL_TIME_TEMPLATE       = q/travel_time.tt/;
my $RESULTS_PAGE_TEMPLATE      = q/travel_results.tt/;
my $TRAVEL_TIME_QUICK_TEMPLATE = q/travel_time_quick.tt/;
my $TRAVEL_TIME_START          = q{/travel_time};
my $TRAVEL_TIME_QUICK          = q{/quick};
my $MIN_ADDR_FIELD_LEN         = 3;
my $MIN_ADDR_STATE_FIELD_LEN   = 2;
my $MAX_ADDR_FIELD_LEN         = 80;
my $IS_IT_NYC_RX = qr/Bronx\s*?$|Brooklyn\s*?$|New York,\s*?NY|New York,\s*?New
          York|New York City|Queens\s*?$|Staten
          Island\s*?$|Brooklyn,|Bronx,|Queens,/i;
my $GET_COUNTY_RX = qr/,\s*?(?<county>\w+\s?\w*?\s?\w*?)(?=$)/;
my $NYC_MANHATTAN_RX =
  qr/new york|new york city|new york county|manhattan|nyc/i;
my $NYC_QUEENS_RX   = qr/queens|queens county/i;
my $NYC_BROOKLYN_RX = qr/kings|brooklyn|brooklyn county/i;
my $NYC_BRONX_RX    = qr/bronx|bronx county/i;
my $NYC_SI_RX       = qr/richmond|staten island|richmond county/i;

my $NYC_5_BORO_RX =
qr/$NYC_MANHATTAN_RX|$NYC_BRONX_RX|$NYC_BROOKLYN_RX|$NYC_QUEENS_RX|$NYC_SI_RX/i;
my $NYC_OUTER_BORO_RX =
  qr/$NYC_BRONX_RX|$NYC_BROOKLYN_RX|$NYC_QUEENS_RX|$NYC_SI_RX/i;

#------ Fixed travel time in New York City
my $NYC_INTER_BORO_TT  = 45;
my $NYC_WITHIN_BORO_TT = 30;
my %MY_ERRORS;

#------ Google Matrix Element status codes
my $OK           = q/OK/;
my $NOT_FOUND    = q/NOT_FOUND/;
my $ZERO_RESULTS = q/ZERO_RESULTS/;

#----- Quickfix for a Dancer2 bug not being able to read Config file
set layout => 'main';

#---- Connect to Database
hook before => sub {
    connect_to_cities() unless $DBH;
    error 'Didnt get the DBH!' unless $DBH;
};

#-------------------------------------------------------------------------------
#  GET
#-------------------------------------------------------------------------------
get $TRAVEL_TIME_START => sub {
    debug 'Got to render regular tt page.';
    %MY_ERRORS = ();
    my $tm_form = create_address_form( { fif_from_value => 1 } );

    my $init_object = {
        addresses => [
            config->{Address}{origins}{1},
            config->{Address}{destinations}{1},
            config->{Address}{destinations}{2},
        ],
    };

    $tm_form->process( init_object => $init_object );

    #    $tm_form->field('addresses')->add_extra(1);

    template $TRAVEL_TIME_TEMPLATE,
      {
        title               => config->{Display}{tm_title},
        travel_time_heading => config->{Display}{tm_heading_1},
        tm_form             => $tm_form,
        info_message        => config->{Display}{intro_message},
        travel_time_start   => $TRAVEL_TIME_START
      };
};

#-------------------------------------------------------------------------------
#  POST
#-------------------------------------------------------------------------------
post $TRAVEL_TIME_START => sub {
    %MY_ERRORS = ();
    my $tm_form = create_address_form();

    process_error( { Error => 'Should never get here!!!!!!', } )
      unless $tm_form;
    debug 'Travel time address form was re-created.';

    # Each parm is a key value
    $tm_form->process( params => {params} );

    debug 'Travel time address form was processed.';

    my %template_vars = (
        title               => config->{Display}{tm_title},
        travel_time_heading => config->{Display}{tm_heading_2},
        tm_form             => $tm_form,
        travel_time_start   => $TRAVEL_TIME_START
    );

    my $mover_distance_results;
    if ( $tm_form->validated && $tm_form->is_valid ) {
        debug "Form is valid!";
        my $itinerary_array = create_itineray_array_from_fh($tm_form);
        debug 'Itinerary array is ' . dump $itinerary_array;
        $mover_distance_results = get_all_itinerary_data($itinerary_array);

        #------ Check for any errors returned from travel time
        #      processing
        my ( $template, $t_vars ) = create_final_template(
            {
                mover_distance_results => $mover_distance_results,
                template_vars          => \%template_vars,
            }
        );
        debug 'The template to be rendered is ' . $template;
        template $template, $t_vars;
    }
    else {

        debug "Form is Invalid!";

        #------ form error
        $template_vars{warning_message} =
          'Please check that the addresses(s) are valid.';
        template $TRAVEL_TIME_TEMPLATE, \%template_vars;
    }

};

#-------------------------------------------------------------------------------
#  Quick Method
#-------------------------------------------------------------------------------
get $TRAVEL_TIME_QUICK => sub {
    debug 'Got to quick travel time GET page.';
    %MY_ERRORS = ();

    #----- Must be at least two address fields in itinerary form.
    template $TRAVEL_TIME_QUICK_TEMPLATE,
      {
        title                => config->{Display}{tm_title},
        travel_time_heading  => config->{Display}{tm_heading_1},
        info_message         => config->{Display}{intro_message},
        what_to_do           => config->{Display}{Quick}{what_to_do},
        form_name            => config->{Form}{Quick}{form_name},
        form_action          => $TRAVEL_TIME_QUICK,
        form_method          => config->{Form}{Quick}{form_method},
        travel_time_start    => $TRAVEL_TIME_QUICK,
        quick_form_addresses => [ '', '' ],
      };

};

post $TRAVEL_TIME_QUICK => sub {
    debug 'Got to quick travel time POST page.';
    %MY_ERRORS = ();
    debug 'Quick form params are : ' . dump params;

    return redirect $TRAVEL_TIME_QUICK unless ( keys params );

    my $itinerary_array = create_itinerary_array( {params} );
    debug 'Itinerary : ' . dump( $itinerary_array // 'EMPTY' );

    my $mover_distance_results = get_all_itinerary_data($itinerary_array)
      if $itinerary_array;

    my ( $template, $template_vars ) = create_final_template(
        {
            mover_distance_results => $mover_distance_results,
            itinerary_array        => $itinerary_array,
            template_vars          => {
                title               => config->{Display}{tm_title},
                travel_time_heading => config->{Display}{tm_heading_1},
                info_message        => config->{Display}{intro_message},
                form_name           => config->{Form}{Quick}{quick_form},
                form_action         => $TRAVEL_TIME_QUICK,
                form_method         => config->{Form}{Quick}{form_method},
                travel_time_start   => $TRAVEL_TIME_QUICK,
            }
        }
    );

    template $template, $template_vars;
};

#-------------------------------------------------------------------------------
#    AJAX
#-------------------------------------------------------------------------------
ajax '/city_states' => sub {
    debug 'Using AJAX,  because it makes everything wonderful.';

    #------ Trim  whitespace from lhs and append the '%' SQL match char.
    #       This will handle searches like 'Sunn,      New York' (Sunnyside, New York)
    #       or                             'Kew Gar,      New York' (Key Gardens,  New York)
    #       or                             'Kew,New York'
    my @find_params =
      map { $_ =~ s/^\s+//; s/\s+\z//; $_ . '%' }
      split( ',', params->{find} );
    debug 'The find params array now contains : ' . dump @find_params;

    my $csc_arr;

    #------ Allow some short cuts for the Big Apple
    if ( $find_params[0] =~ /^(nyc|manhattan|base)%\z/i ) {
        $csc_arr->[0] = [ 'New York City', 'New York', 'New York County' ];
    }
    else {

        #----- Search DB for City and Counties matching the search params.
        connect_to_cities() unless $DBH;
        process_error( { Error => 'Unable to connect to the City, State,
                county database! Please try later!', } ) unless $DBH;
        $csc_arr = select_city_state_cty( $DBH, \@find_params );
    }

    #------ Returns sorted list of Cities, States and Counties to
    #       city-states.js
    { city_states => $csc_arr };
};

#-------------------------------------------------------------------------------
#   Wrong route
#-------------------------------------------------------------------------------
any qr{.*} => sub {

    #------ All bad routes to to the Quick Calculator for now
    return redirect $TRAVEL_TIME_QUICK;
};

#-------------------------------------------------------------------------------
#  Error Page
#-------------------------------------------------------------------------------
get '/error_page/:vars' => sub {
    my $vars = params->{vars};
    template $ERROR_PAGE_TEMPLATE, {
        %$vars,

        #        error_page_heading => config->{Display}{unknown_error_message}
        error_messages => \%MY_ERRORS,
        home           => $TRAVEL_TIME_QUICK,
    };
};

#-------------------------------------------------------------------------------
#
#                           Subroutines
#
#-------------------------------------------------------------------------------
#  Prepare error messages.
#-------------------------------------------------------------------------------
sub process_error {
    my $errors = shift;
    for my $err (keys %errors){
     $MY_ERRORS{$err} = $errors{$err};
    }

    if ( keys %MY_ERRORS ) {
        error "Got these errors : \n" . dump %MY_ERRORS;
    }
    else {
        error 'Got some unknown error!';
        $MY_ERRORS{message} =
          ( config->{Display}{unknown_error_message}
              || 'Something bad happened!' );
    }
    redirect '/error_page';
}

#-------------------------------------------------------------------------------
#  Create  FormBuilder Form
#-------------------------------------------------------------------------------
sub create_address_form {
    my $params = shift;
    my $address_form;
    try {
        $address_form = Mover::Form::Travel::Matrix->new( fif_from_value => 1 );
    }
    catch {
        error 'Got error creating address form : ' . $_;
        process_error(
            {
                Error => 'The Travel Matrix Address Form is really messed up!',
                form_error => substr( $_, 0, 400 ),
            }
        );
    };
    return $address_form;
}

#-------------------------------------------------------------------------------
#  create_final_template
#  Create the final template after processing the requested itinerary.
#  Check for any errors returned from distance matrix or travel time
#  processing.
#  Pass:
#       {
#           tm_form => $tm_form,  # if using HTML::FormHandler
#           mover_distance_results => $mover_distance_results,
#           template_vars          => \$template_vars,
#           itinerary_array        => $itinerary_array, #original addresses
#       });
#
#  Returns a ready to render template and \%template_vars.
#-------------------------------------------------------------------------------
sub create_final_template {
    my $template_data          = shift;
    my $mover_distance_results = $template_data->{mover_distance_results};
    my $itinerary_array        = $template_data->{itinerary_array}
      if $template_data->{itinerary_array};
    my $template_vars = $template_data->{template_vars};

    my $tm_form = $template_vars->{tm_form}
      if $template_vars->{tm_form};
    if ($tm_form) {
        debug 'We are using the FormBuilder Form';
    }
    else {
        debug 'We are using the quick form.';
    }
    my $template;
    if ( ( keys %MY_ERRORS ) or ( not $mover_distance_results ) ) {

        #------ Failure
        %$template_vars = (
            %$template_vars,
            info_message  => 'Please check that the addresses(s) are valid.',
            error_message => config->{Display}{error_message},
            my_errors     => \%MY_ERRORS,
            tm_form         => $tm_form,            # FormHandler only
            itinerary_array => $itinerary_array,    # Quick Form
            form_is_valid   => $FALSE,
        );
        $template =
          $tm_form ? $TRAVEL_TIME_TEMPLATE : $TRAVEL_TIME_QUICK_TEMPLATE;
    }
    else {

        #----- Success!
        %MY_ERRORS = ();
        debug 'Final travel results are : ' . dump $mover_distance_results;
        %$template_vars = (
            %$template_vars,
            result_heading  => config->{Display}{result_heading},
            success_message => config->{Display}{success_message}
              || 'With the help of the Google Distance Matrix!',
            results_table_heading  => config->{Display}{results_table_heading},
            mover_distance_results => $mover_distance_results,
            form_is_valid          => $TRUE,
        );
        $template =
          $tm_form ? $RESULTS_PAGE_TEMPLATE : $TRAVEL_TIME_QUICK_TEMPLATE;
    }
    return ( $template, $template_vars );
}

#-------------------------------------------------------------------------------
#  Convert the form addresses to an array of addresses
#  Pass the FormHandler form with the addresses
#-------------------------------------------------------------------------------
sub create_itineray_array_from_fh {
    my $tm_form = shift;
    croak 'Must send the form with the address paramaters!'
      unless ($tm_form);
    my @address_array;

    #------ Get The Addresses
    foreach my $address ( $tm_form->field('addresses')->fields ) {
        my %address_hash;
        foreach my $field ( $address->fields ) {
            $address_hash{ $field->name } = $field->value;
        }
        push @address_array, \%address_hash;
    }
    return \@address_array;
}

#-------------------------------------------------------------------------------
#  Takes the hidden address field params h-address-1, h-address-2.......
#  Grabs the address stored in the format city,state,county
#  Returns an array of each address stored in order.
#-------------------------------------------------------------------------------
sub create_itinerary_array {
    croak 'Must send the quick form paramaters to convert to itinerary array!'
      unless ( ref( $_[0] ) eq 'HASH' );
    my $in_params = validate_quick_form(shift);
    return if ( keys %MY_ERRORS );

    #------ Sort Addresses in Itinerary order.
    #       The addresses we want are the ones in the hidden fields prefixed
    #       with 'h-address-'.
    my @address_array = map {
            $in_params->{$_}->[0] . ', '
          . $in_params->{$_}->[1] . ', '
          . $in_params->{$_}->[2]
      }
      sort {
        substr( $a, index( $a, '-', 2 ) + 1 ) <=>
          substr( $b, index( $b, '-', 2 ) + 1 )
      } grep { /^h-address-/ } keys %$in_params;

    debug 'Quick itinerary array: ' . dump @address_array;
    if ( @address_array < 2 ) {
        $MY_ERRORS{input_address} =
          'Cannot handle the addresses in this format!';
        return;
    }

    return \@address_array;
}

#-------------------------------------------------------------------------------
#  Combine the Itinerary array with the Google Distance Matrix data
#  to come up with the Mover Travel Time between each location.
#-------------------------------------------------------------------------------

sub get_all_itinerary_data {
    my $itinerary_array = shift;
    my @goog_matrix_results_with_tt;
    my $total_mover_travel_time_minutes;

    #------- Get the array of Google Matrix Element Results
    #        Add a new key/value to the Element results HashRef
    #        This key/value pair will be
    #        'mover_travel_time' => $mover_travel_time
    #
    my $Gm = get_google_travel_matrix();
    return unless $Gm;

    my $goog_matrix_results = get_google_matrix_data( $Gm, $itinerary_array )
      if $Gm;
    return unless $goog_matrix_results;
    for my $goog_mx_el_result (@$goog_matrix_results) {
        if ( $goog_mx_el_result->{element_status} eq $OK ) {
            my $mover_travel_time_minutes;

            #------Get the origin and destination county
            (
                $goog_mx_el_result->{origin_county},
                $goog_mx_el_result->{destination_county}
            ) = get_origin_and_dest_county($goog_mx_el_result);

            #------Get the travel time and the running total travel time
            #      To and from NYC use different metrics for converting
            #      Use the Original address sent to Google, as it contains the
            #      county info.
            #todo Process NYC times for the old long form style calculation
            $total_mover_travel_time_minutes += $mover_travel_time_minutes =
              calculate_travel_time($goog_mx_el_result);

            %$goog_mx_el_result = (
                %$goog_mx_el_result,
                mover_travel_time_minutes => $mover_travel_time_minutes,
                mover_travel_time =>
                  convert_minutes_to_hours_minutes($mover_travel_time_minutes),
            );

        }
        push @goog_matrix_results_with_tt, $goog_mx_el_result;
    }
    return \@goog_matrix_results_with_tt;
}

#-------------------------------------------------------------------------------
#  Interactions with Google
#-------------------------------------------------------------------------------

sub get_google_travel_matrix {
    my $GoogMx;
    try {
        $GoogMx = Google::Travel::Matrix->new( config->{Google}{Params}, );
    }
    catch {
        $MY_ERRORS{goog_matrix} = "Failed to connect to Google!</br> Please try
        again.";
        error 'Unable to create Google::Travel::Marix: ' . $_;
    };
    return $GoogMx;
}

sub get_google_matrix_data {
    my $GoogTrMatrix = shift;
    croak 'Must pass Google::Travel::Matrix object! ' unless $GoogTrMatrix;
    my $itinerary_array = shift;
    croak 'Must pass an Itinerary array! ' unless $itinerary_array;
    my ( @results_arr, @elements );
    debug 'My input itinerary details are : ' . dump $itinerary_array;

    try {

        #------ Treat the first itinerary address as the origin
        $GoogTrMatrix->origins( shift @$itinerary_array );
        $GoogTrMatrix->destinations($itinerary_array);
        @elements = @{ $GoogTrMatrix->get_all_elements() };
    }
    catch {
        error 'Got an error with the address(s): ' . $_;
        $MY_ERRORS{goog_matrix_addresses} = "Got an error with the addresses. ";
    };

    foreach my $distance_element (@elements) {

        #------ Google gives the distance value in meters. It gives a text
        #       value in metric or imperial measurement, but the meters value
        #       is consistant.

        push @results_arr, {
            origin_address      => $distance_element->{origin_address},
            destination_address => $distance_element->{destination_address},
            original_origin_address =>
              $distance_element->{original_origin_address},
            original_destination_address =>
              $distance_element->{original_destination_address},
            element_status        => $distance_element->{element_status},
            element_duration_text => $distance_element->{element_duration_text},
            element_duration_value =>
              $distance_element->{element_duration_value},
            element_distance_text => $distance_element->{element_distance_text},

            #------ This distance is ALWAYS in Meters.
            element_distance_value =>
              $distance_element->{element_distance_value},
            distance_in_miles => convert_from_meters_to_miles(
                $distance_element->{element_distance_value}
            ),
        };
    }
    debug 'The results array is ' . dump @results_arr;
    return \@results_arr;
}
#
#-------------------------------------------------------------------------------
#  Get Origin and Destination County's
#  Pass the Google Matrix Data
#  Return list of origin county and dest county.
#-------------------------------------------------------------------------------
sub get_origin_and_dest_county {
    my $matrix_data = shift;
    return (
        get_county( $matrix_data->{original_origin_address} ),
        get_county( $matrix_data->{original_destination_address} )
    );
}

#-------------------------------------------------------------------------------
#  Get County
#  Pass the original User Inputted Address
#-------------------------------------------------------------------------------
sub get_county {
    my $city_state_county = shift;
    if ( $city_state_county =~ /$GET_COUNTY_RX/ ) {
        return $+{county};
    }
}

#-------------------------------------------------------------------------------
#   calculate_travel_time
#  Calculate the travel time between two locations.
#  Different metrics used for points originating or ending in New York
#  New York needs special processing
#  1. If Origin or Destination is NYC, then the first 20 miles is 1 hour
#  2. If Origin or Destination is NYC, and the same Borough, then travel time
#     is half hour(30 mins).
#  3. If Origin or Destination is NYC, and the different Borough, then travel time
#     is 45 mins.
#
#     Pass one Google Matrix Element result (contains one from and one to
#     address as well as distances etc.)
#     Only works when the county is included with the Google Data
#-------------------------------------------------------------------------------
sub calculate_travel_time {
    my $goog_data = shift;

    my $orig_county = $goog_data->{origin_county};
    my $dest_county = $goog_data->{destination_county};

    #------Get the origin and destination county if not stored already
    ( $orig_county, $dest_county ) = get_origin_and_dest_county($goog_data)
      unless ( $orig_county && $dest_county );

  NYC_SWITCH: {

        #------- Inside Manhattan?
        (        ( $orig_county =~ qr/^$NYC_MANHATTAN_RX$/ )
              && ( $dest_county =~ qr/^$NYC_MANHATTAN_RX$/ ) )
          && do {
            return $NYC_WITHIN_BORO_TT;
            last NYC_SWITCH;
          };

        #------- Inside Brooklyn?
        (        ( $orig_county =~ qr/^$NYC_BROOKLYN_RX$/ )
              && ( $dest_county =~ qr/^$NYC_BROOKLYN_RX$/ ) )
          && do {
            return $NYC_WITHIN_BORO_TT;
            last NYC_SWITCH;
          };

        #------- Inside Bronx?
        (        ( $orig_county =~ qr/^$NYC_BRONX_RX$/ )
              && ( $dest_county =~ qr/^$NYC_BRONX_RX$/ ) )
          && do {
            return $NYC_WITHIN_BORO_TT;
            last NYC_SWITCH;
          };

        #------- Inside Queens?
        (        ( $orig_county =~ qr/^$NYC_QUEENS_RX$/ )
              && ( $dest_county =~ qr/^$NYC_QUEENS_RX$/ ) )
          && do {
            return $NYC_WITHIN_BORO_TT;
            last NYC_SWITCH;
          };

        #------- Inside Staten Island?
        (        ( $orig_county =~ qr/^$NYC_SI_RX$/ )
              && ( $dest_county =~ qr/^$NYC_SI_RX$/ ) )
          && do {
            return $NYC_WITHIN_BORO_TT;
            last NYC_SWITCH;
          };

   #------ Not within a Borough,  It may be from one Borough to another Borough?
        (        ( $orig_county =~ qr/^$NYC_5_BORO_RX$/ )
              && ( $dest_county =~ qr/^$NYC_5_BORO_RX$/ ) )
          && do {
            return $NYC_INTER_BORO_TT;
            last NYC_SWITCH;
          };

      #------ Not within a Borough,  Not withihin the 5 Boroughs,  maybe one
      #       location  is within the 5 Boroughs and one location is outside the
      #       city?
        (        ( $orig_county =~ qr/^$NYC_5_BORO_RX$/ )
              || ( $dest_county =~ qr/^$NYC_5_BORO_RX$/ ) )
          && do {
            return convert_miles_to_travel_time_nyc(
                $goog_data->{distance_in_miles} );
            last NYC_SWITCH;
          };

        last NYC_SWITCH;
    };    #------ END NYC LOOP

    #------ No location within the 5 boroughs of NYC
    return convert_miles_to_travel_time( $goog_data->{distance_in_miles} );
}

#-------------------------------------------------------------------------------
#  Is the address in NYC,  Including Manhattan, Bronx, Brooklyn,Queens, Staten
#  Island
#  Pass the address; addr1, addr2, city, state, zip
#  Returns $TRUE if the address is in the 5 Boroughs
#          $FALSE otherwise.
#-------------------------------------------------------------------------------
sub is_address_nyc {
    my $address = shift;
    debug 'Checking if this address ' . $address . ' is in NYC';

    #------ See if it is at least NY State
    return $FALSE unless ( $address =~ /NY|New York/i );
    debug $address . ' is in New York State';

    return $TRUE
      if ( $address =~ /$IS_IT_NYC_RX/ );

    #------ If there is a zip code and it is a NYC
    #       zip, we are lucky(or not depending on your perspective).
    if ( $address =~ $RE{zip}{US}{ -extended => ['allow'] }{-keep} ) {
        my $zip         = $4;
        my $first_three = $3;
        debug 'US five digit Zip is ' . $zip;

        #------- Definately not NYC if the first 3 digits of Zip is not NYC
        return $FALSE if $first_three < config->{City}{NYC}{zip_code_three_max};

        #------- Check for match with nyc_zips database table
        my $matching_zip;
        connect_to_cities() unless $DBH;
        try {
            $matching_zip = select_nyc_zip( $DBH, [$zip] );
        }
        catch {
            error 'Problem accessing zip info from cities database: ' . $_;
            $MY_ERRORS{db_error} = $_;
        };
        return $TRUE if ( $matching_zip && ( @$matching_zip >= 1 ) );
    }
    return $FALSE;
}

#-------------------------------------------------------------------------------
#  Convert Miles To Truck Travel Time
#  Returns the time in minutes;
#-------------------------------------------------------------------------------

=head2 convert_miles_to_travel_time
 Uses this method:
    The first 40 miles is 60 minutes.
    Each 10 miles after that is 15 mins
    Note:  
        15 minutes is the smallest time unit.
        The given milage is converted to an integer, therefore removing any fractions.
        This integer milage is rounded up to next highest 10 miles.

=cut

sub convert_miles_to_travel_time {

    #------ Not concerned with faction of mile.
    my $distance = abs(shift);
    return 60 if ( $distance <= 40 );
    my $time_minutes = 60;
    $distance -= 40;
    my $mod;
    my $dist_rounded =
      ( ( $mod = $distance % 10 ) == 0 )
      ? int $distance
      : int( $distance += ( 10 - $mod ) );

    return $time_minutes += ( $dist_rounded / 10 ) * 15;
}

=head2 convert_miles_to_travel_time_nyc
 Uses this method for journeys starting or ending in NYC(including 5 boroughs):
    The first 20 miles is 60 minutes.
    Each 10 miles after that is 15 mins
    Note:  
        15 minutes is the smallest time unit.
        The given milage is converted to an integer, therefore removing any fractions.
        This integer milage is rounded up to next highest 10 miles.

=cut

sub convert_miles_to_travel_time_nyc {

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
    return 0 unless $_[0];
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
    return 0 unless $_[0];
    my $miles = $_[0] * 0.000621371;
    return sprintf( "%.1f", $miles );
}

sub convert_from_miles_to_meters {
    return 0 unless $_[0];
    return $_[0] * 1609.34;
}

#-------------------------------------------------------------------------------
#  Open File
#-------------------------------------------------------------------------------
sub slurp_file {
    my $file = shift;
    open my $fh, '<', $file
      or die "Cannot open '$file' for reading: $!";
    return do { local $/; <$fh> };
}

#-------------------------------------------------------------------------------
#  Connect to the Cities Database
#-------------------------------------------------------------------------------
sub connect_to_cities {
    try {
        $DBH = db_handle( config->{Bootstrap}{Typeahead}{city_db} );
    }
    catch {
        error 'Problem connecting to cities database: ' . $_;
        $MY_ERRORS{db_error} = $_;
    };
}

#-------------------------------------------------------------------------------
#  Validation
#-------------------------------------------------------------------------------
sub validate_quick_form {
    croak 'Can only validate params as a HashRef!'
      unless ( ref( $_[0] ) eq 'HASH' );
    my $in_params = shift;

    my %addr_element = ( 0 => 'City', 1 => 'State', 2 => 'County' );

    #------ Split each address into its components, trim and validate
    for my $p ( keys %$in_params ) {
        my @city_state_cty = split( ',', $in_params->{$p} );
        @city_state_cty =

          #          grep {/\P{IsAlpha}| |\-/}
          grep { /\w| |\-/ }
          map { s/^\s+//; s/\s+\z//; $_ } @city_state_cty;

        #          map { s/^\s+//; s/\s+\z//; s/\W/ /g; $_ } @city_state_cty;
        debug 'City, state ,  county after trimming are : ' . join ',',
          @city_state_cty;
        if ( @city_state_cty < 2 ) {
            $MY_ERRORS{input_address} = 'You must enter a City/Town, State
        Name, and even the County too!';
            return;
        }

        #------ Verify lengths of city, state and county
        #------ city = 0 state = 1 county = 2
        for ( my $i = 0 ; $i <= $#city_state_cty ; $i++ ) {

            my $length = length( $city_state_cty[$i] // q// );

            #--- State has a smaller min_length to allow for state codes.
            my $min_length = (
                  $i == 1
                ? $MIN_ADDR_STATE_FIELD_LEN
                : $MIN_ADDR_FIELD_LEN
            );
            if ( $length < $min_length ) {
                error $addr_element{$i}
                  . ' name is too short! '
                  . ( $city_state_cty[$i] // '<EMPTY>' );
                $MY_ERRORS{ $addr_element{$i} } =
                  $addr_element{$i} . ' name is too short!';
            }
            if ( $length > $MAX_ADDR_FIELD_LEN ) {
                error $city_state_cty[$i] . ': '
                  . $addr_element{$i}
                  . '  name is too long!';
                $MY_ERRORS{ $addr_element{$i} } =
                  $addr_element{$i} . ' name is too long!';
            }

           #------ Verify State Name. If state code given, convert it to a state
           #       name.
           #       Only for the state stored in the hidden field
            if ( $i == 1 && $p =~ /^h-address/ ) {

                #----- If it is not a state name,  see if it is a State Code
                #      that can be converted to a state name. If not, then
                #      it must be invalid.
                if ( not get_state_code_from_name( $city_state_cty[$i] ) ) {
                    if ( my $state_name =
                        get_state_name_from_code( $city_state_cty[$i] ) )
                    {
                        $city_state_cty[$i] = $state_name;
                    }
                    else {
                        error 'State error for : ' . $city_state_cty[$i];
                        $MY_ERRORS{input_address} =
                          $city_state_cty[$i] . ' Is an invalid state name!';
                    }
                }
            }
        }
        $in_params->{$p} = \@city_state_cty;
    }

    return if ( keys %MY_ERRORS );
    debug 'Validated params are : ' . dump $in_params;

    return $in_params;
}

#-------------------------------------------------------------------------------
true;

__END__

=head1 NAME
 TravelTime -  Calculate Truck Travel Times
=cut

=head1 VERSION
Version 0.02
=cut

=head1 SYNOPSIS
                                           



=cut

=head1 DESCRIPTION
 This application allows a user to calculate the standard travel time between
 two points based on the New York City Department of Transportation guidelines
 for Household Goods Carriers.
 The first 40 miles is 1 hour 
 If the start or end point is NYC then the first 20 miles is 1 hour
 Each subsequent 40 miles is 1 hour( or each 10 miles is 15 minutes)
 Within NYC the Travel time within a Borough is 30 minutes. 
 Between boroughs it is 45 minutes.
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
          sub { convert_from_meters_to_miles($element_distance_value) },
        mover_travel_time_minutes =>
          sub { convert_miles_to_travel_time($distance_in_miles) },
        mover_travel_time => {
            hours         => int( $minutes / 60 ),
            minutes       => $minutes % 60,
            hours_minutes => $minutes / 60,
        },
    }
=cut
