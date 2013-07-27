# ABSTRACT: Handy Module Ineractions with SQLite Database
#-------------------------------------------------------------------------------
#  Creates an SQLite Database handle
#  Pass a SQLite database name
#  Pass a hashref of attributes;
#  Also exports other database functions
#-------------------------------------------------------------------------------
package MyDatabase;
use Modern::Perl qw/2012/;
use autodie;
use DBI;
use Carp 'croak';
use Exporter::NoWork;
use Data::Dump qw/dump/;
use utf8::all;

#-------------------------------------------------------------------------------
#  SQL Statements
#-------------------------------------------------------------------------------
#------ Select a us place name and state from view place_name given a few
#      chars of that place_name. Unique values only.
#      The View places_states is already DISTINCT and orderd by places and state codes.
my $select_city_state_cty_like_city = <<"SELECT_CITIES";
    SELECT place_name, state_name, county_name
    FROM places_states_cty WHERE place_name like ? 
SELECT_CITIES

#------ Select a us place name and state from view place_name given a few
#      chars of that place_name and a few chars of the state name.
#      Unique values only.
#      The View places_states is already DISTINCT and orderd by places and state codes.
my $select_city_state_cty_like_city_st = <<"SELECT_CITIES_ST";
    SELECT place_name, state_name, county_name
    FROM places_states_cty
    WHERE place_name like ? 
    AND   state_name like ?
SELECT_CITIES_ST

#    ORDER BY place_name, state_code, us_cities.postal_code

#------- Select a NYC Zip codes from the NYC 5 Borough Zip codes
my $select_nyc_zip = <<"SELECT_NYC_ZIPS";
    SELECT postal_code
       FROM nyc_zips
       WHERE postal_code=?
SELECT_NYC_ZIPS

#------- Select NYC place names,  counties,  and zip codes
#        This view is already Orderd by place_name,county_name and postal
#        code.
my $select_nyc_places_ord = <<"SELECT_NYC_PLACES";
    SELECT place_name, county_name, postal_code 
    FROM nyc_places
SELECT_NYC_PLACES

#-------------------------------------------------------------------------------
#  States List
#-------------------------------------------------------------------------------
#----- States includes the District of Columbia
my $us_states = {
    'AL' => 'Alabama',
    'AK' => 'Alaska',
    'AZ' => 'Arizona',
    'AR' => 'Arkansas',
    'CA' => 'California',
    'CO' => 'Colorado',
    'CT' => 'Connecticut',
    'DC' => 'District Of Columbia',
    'DE' => 'Delaware',
    'FL' => 'Florida',
    'GA' => 'Georgia',
    'HI' => 'Hawaii',
    'ID' => 'Idaho',
    'IL' => 'Illinois',
    'IN' => 'Indiana',
    'IA' => 'Iowa',
    'KS' => 'Kansas',
    'KY' => 'Kentucky',
    'LA' => 'Louisiana',
    'ME' => 'Maine',
    'MD' => 'Maryland',
    'MA' => 'Massachusetts',
    'MI' => 'Michigan',
    'MN' => 'Minnesota',
    'MS' => 'Mississippi',
    'MO' => 'Missouri',
    'MT' => 'Montana',
    'NE' => 'Nebraska',
    'NV' => 'Nevada',
    'NH' => 'New Hampshire',
    'NJ' => 'New Jersey',
    'NM' => 'New Mexico',
    'NY' => 'New York',
    'NC' => 'North Carolina',
    'ND' => 'North Dakota',
    'OH' => 'Ohio',
    'OK' => 'Oklahoma',
    'OR' => 'Oregon',
    'PA' => 'Pennsylvania',
    'RI' => 'Rhode Island',
    'SC' => 'South Carolina',
    'SD' => 'South Dakota',
    'TN' => 'Tennessee',
    'TX' => 'Texas',
    'UT' => 'Utah',
    'VT' => 'Vermont',
    'VA' => 'Virginia',
    'WA' => 'Washington',
    'WV' => 'West Virginia',
    'WI' => 'Wisconsin',
    'WY' => 'Wyoming',
};

#-------------------------------------------------------------------------------
#  Connect to a SQLite Database
#  Set foreigh keys on.
#-------------------------------------------------------------------------------
sub db_handle {
    my $db_file = shift
      or croak "db_handle() requires a database name";
    my $attr = shift;
    $attr ||= {
        RaiseError       => 1,
        PrintError       => 0,
        AutoCommit       => 1,
        FetchHashKeyName => 'Name_lc',
        sqlite_unicode => 1, 
    };
    no warnings 'once';
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$db_file",
        "",    # no username required
        "",    # no password required
        $attr,
    ) or die $DBH::errstr;

    $dbh->do("PRAGMA foreign_keys = ON");

    return $dbh;
}

#-------------------------------------------------------------------------------
#  Prepare the 'Select City State' Statement
#  Get City State information from the Database
#  With JUST THE CITY INFORMATION in the predicate
#-------------------------------------------------------------------------------
#sub prepare_select_city_state_cty_city {
#    my $dbh = shift
#      or croak 'prepare_select_city_state_cty() requires a database handle.';
#    my ($select_statement) = ( $_[0] || $select_city_state_cty_like_city );
#    return $dbh->prepare($select_statement) or die $DBH::errstr;
#}

#-------------------------------------------------------------------------------
#  Prepare the 'Select City State' Statement
#  Get City State information from the Database
#  With the FIRST CHARS OF THE CITY AND FIRST CHARS OF THE STATE in the
#  predicate
#-------------------------------------------------------------------------------
#sub prepare_select_city_state_cty_city_st {
#    my $dbh = shift
#      or croak 'prepare_select_city_state_cty() requires a database handle.';
#    my ($select_statement) = ( $_[0] || $select_city_state_cty_like_city_st );
#    return $dbh->prepare($select_statement) or die $DBH::errstr;
#}

#-------------------------------------------------------------------------------
#  Prepare, execute and return City, State and County's
#  Pass the bind params as an ArrayRef
#  One bind param, will search by the place_name only
#  Two bind params,  will search by the place_name and state_name only
#-------------------------------------------------------------------------------
sub select_city_state_cty {
    my $dbh = shift
      or croak 'select_nyc_zip() requires a database handle.';
    my $bind_city_st = shift
      or croak
'Must send a city name and possibly a state name as a bind value to select_city_state_cty!';
    #------ One bind param means the search is by place_name
    #       Two bind params means the search is by place_name, state_name
    if ( @$bind_city_st == 1 ) {
        return $dbh->selectall_arrayref( $select_city_state_cty_like_city,
            undef, @$bind_city_st )
          or die $DBH::errstr;
    }
    else {
        return $dbh->selectall_arrayref( $select_city_state_cty_like_city_st,
            undef, @$bind_city_st )
          or die $DBH::errstr;
    }

}

#-------------------------------------------------------------------------------
#  Prepare, execute and return a NYC Zip Code if the Select is successful.
#  Pass the bind params as an ArrayRef
#-------------------------------------------------------------------------------
sub select_nyc_zip {
    my $dbh = shift
      or croak 'select_nyc_zip() requires a database handle.';
    my $bind_zip_ref = shift or croak 'Must send a zip code as a bind value to
    select_nyc_zip!';
    return $dbh->selectrow_arrayref( $select_nyc_zip, undef, @$bind_zip_ref )
      or die $DBH::errstr;
}

#-------------------------------------------------------------------------------
# Prepare
#  Get New York City place_names, County and Zip from
#  View nyc_places.
#-------------------------------------------------------------------------------
sub prepare_select_nyc_places_ord {
    my $dbh = shift
      or croak 'prepare_select_nyc_places_ord() requires a database handle.';
    my ($select_statement) = ( $_[0] || $select_nyc_places_ord );
    return $dbh->prepare($select_statement) or die $DBH::errstr;
}

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
#  Execute the Select statement
#
#  Returns the Statement handle or undef if it fails.
#  Can pass placeholder params if necessary.
#-------------------------------------------------------------------------------
sub execute_select {
    my $sth = shift or croak 'execute_select() requires a SQL statment handle.';
    my $bind_params_ref = shift;
    croak 'Bind params must be an ArrayRef!'
      unless ( ref $bind_params_ref eq 'ARRAY' );

    return $sth->execute(@$bind_params_ref) or die $DBH::errstr;
}

#-------------------------------------------------------------------------------
#  Fetchall
#  Returns an ArrayRef of ArrayRef's of data
#  Can pass slice or parms.
#-------------------------------------------------------------------------------
sub fetchall_arrayref {
    my $sth = shift
      or croak 'fetchall_arrayref() requires a SQL statment handle.';
    my $slice_or_params = shift;
    if ($slice_or_params) {
        return $sth->fetchall_arrayref($slice_or_params) or die $DBH::errstr;
    }
    else {
        return $sth->fetchall_arrayref() or die $DBH::errstr;
    }
}

#-------------------------------------------------------------------------------
#  FetchRow
#  Returns one row of data.
#-------------------------------------------------------------------------------
sub fetchrow_arrayref {
    my $sth = shift
      or croak 'fetchrow_arrayref() requires an SQL statment handle.';
    return $sth->fetchrow_arrayref() or die $DBH::errstr;
}

#-------------------------------------------------------------------------------
#   US States
#-------------------------------------------------------------------------------
sub get_state_codes {
    return sort keys %$us_states;
}

sub get_state_names {
    return sort values %$us_states;
}

sub get_state_name_from_code {
    my $state_code = uc(shift);
    $state_code =~ s/^\s+//;
    $state_code =~ s/\s+$//;
    my %states     = %$us_states;
    return $states{$state_code};
}

sub get_state_code_from_name {
    my $state_name = shift;
    $state_name =~ s/^\s+//;
    $state_name =~ s/\s+$//;
    my %states     = %$us_states;
    while ( my ( $s_code, $s_name ) = each %states ) {
        if ( ( lc $state_name ) eq ( lc $s_name ) ) {
            return $s_code;
        }
    }
}

#-------------------------------------------------------------------------------
1;

__END__

=pod

=head1 NAME

MyDatabase - Handy Module Ineractions with SQLite Database

=head1 VERSION

version 0.2

=head1 AUTHOR

Austin Kenny <aibistin.cionnaith@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Austin Kenny.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
