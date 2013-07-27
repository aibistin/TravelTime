#!/usr/bin/env perl 
#===============================================================================
#
#
#        USAGE: ./populate-city-db.pl
#
#  DESCRIPTION:
#      Drop and create a SQLite database table us_cities
#      in the cities_db
#      Populate the database with all the data from the US.txt file
#      downloaded from http://www.geonames.org
#      Create a view nyc_zips to contain all zips for the five Boroughs of
#      New York City
#      Create indexes and views.
#
#      OPTIONS: ---
# REQUIREMENTS: --- US.txt from http://www.geonames.org
#         BUGS: ---
#       AUTHOR: Austin Kenny (), aibistin.cionnaith@gmail.com
# ORGANIZATION: Carry On Coding
#      VERSION: 1.0
#      CREATED: 07/01/2013 03:37:51 PM
#     REVISION: ---
#===============================================================================
use Modern::Perl qw/2012/;
use strict;
use warnings;
use autodie;
use utf8::all;
use Data::Dump qw/dump/;
use DBI;
use DBD::SQLite;
use DateTime;
use Text::Unidecode;

use MyDatabase q/db_handle/;

use diagnostics -verbose;

#-------------------------------------------------------------------------------
#  Globals
#-------------------------------------------------------------------------------
#------ US cities file downloaded from geonames.org
my $in_file = qq(/home/austin/Data/UsStatesZips/US.txt);

#------ SQLite databse name
my $db_file = q(cities_db);

open my $us_data, '<:encoding(UTF-8)', $in_file
  or die 'Cannot open the input file, ' . $in_file . ',  because: ' . $!;

my $dbh = db_handle( $db_file,
    { RaiseError => 1, PrintError => 0, AutoCommit => 0, sqlite_unicode => 1, }
);

#  DBI->connect( "dbi:SQLite:dbname=$db_file", "", "",
#    { RaiseError => 1, PrintError => 0, AutoCommit => 0 },
#  );

#-------------------------------------------------------------------------------
#  Main
#-------------------------------------------------------------------------------
create_us_cities_table();
create_us_zip_table();
populate_us_zips_n_cities();
create_view_nyc_zips();
create_view_nyc_places();
create_view_places_states();

#-------------------------------------------------------------------------------
#  Create a table us_cities that will contain geonames data for US cities only
#  Note: The SQL does not specify this Predicate,  but the input file
#  contains only US cities.
#-------------------------------------------------------------------------------
sub create_us_cities_table {
    my $drop_us_cities_sql = <<"DROP_CITIES";
   DROP TABLE if EXISTS us_cities;
DROP_CITIES

    $dbh->do($drop_us_cities_sql);

    say 'Dropped the us_cities table.';

    #    PRAGMA foreign_keys = ON;
    my $create_us_cities_sql = <<"CREATE_CITIES";
    CREATE TABLE IF NOT EXISTS  us_cities (
            country_code          TEXT, 
            postal_code           varchar(20), 
            place_name            varchar(180), 
            state_name           varchar(100), 
            state_code           varchar(20), 
            county_name          varchar(100), 
            county_code          varchar(20), 
            community_name       varchar(100), 
            community_code       varchar(20), 
            latitude              decimal(10, 5), 
            longitude             decimal(10, 5), 
            accuracy              INTEGER, 
            created      TIMESTAMP,
            updated      TIMESTAMP, 
            PRIMARY KEY (postal_code,  place_name), 
            FOREIGN KEY(postal_code) REFERENCES us_zips(postal_code)
            );
CREATE_CITIES

    $dbh->do($create_us_cities_sql);

    my $create_postal_code_idx = <<"PC_INDEX";
CREATE INDEX postal_index ON us_cities(postal_code)
PC_INDEX

    $dbh->do($create_postal_code_idx);

    my $create_place_name_idx = <<"PN_INDEX";
CREATE INDEX place_name ON us_cities(postal_code);
PN_INDEX

    $dbh->do($create_place_name_idx);

    $dbh->commit;

    say 'Created a new cities table.';
}

#-------------------------------------------------------------------------------
#  Create a table of US ZipCodes
#-------------------------------------------------------------------------------
sub create_us_zip_table {
    my $drop_us_zip_sql = <<"DROP_ZIPS";
   DROP TABLE if EXISTS us_zips;
DROP_ZIPS

    $dbh->do($drop_us_zip_sql);

    say 'Dropped the us_zip table.';
    my $pragma_fk = <<"PRAG_FK";
    PRAGMA foreign_keys = ON;
PRAG_FK

    say 'Created FK pragma.';

    my $create_us_zip_sql = <<"CREATE_ZIPS";
    CREATE TABLE IF NOT EXISTS  us_zips(
            postal_code           varchar(20) PRIMARY KEY, 
            updated      TIMESTAMP 
            );
CREATE_ZIPS

    $dbh->do($create_us_zip_sql);

    $dbh->commit;

    say 'Created a new US zip table.';
}

#-------------------------------------------------------------------------------
#  Populate the Zip Code Table and Cities table
#-------------------------------------------------------------------------------
sub populate_us_zips_n_cities {

    #------- Populate the Zips table first
    my $sth_zip = $dbh->prepare(
        "INSERT OR IGNORE
          INTO us_zips(
            postal_code,
            updated
    )
    VALUES (?, ?)"
    );

    my $sth_cit = $dbh->prepare(
        "INSERT INTO us_cities(
            country_code, 
            postal_code,
            place_name, 
            state_name, 
            state_code, 
            county_name, 
            county_code, 
            community_name, 
            community_code, 
            latitude, 
            longitude, 
            accuracy, 
            updated
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,?)"
    );
    my $count = 0;
    while ( my $line = <$us_data> ) {
        chomp($line);
        #------ Convert any spanish chars to english... Marvelous
        $line = unidecode( $line );

        #------ place name : maspeth ,  state_name : New York,  state_code : NY,
        #      county_name : Queens:  county_code : 081
        my (
            $country_code, $postal_code, $place_name,  $admin_name1,
            $admin_code1,  $admin_name2, $admin_code2, $admin_name3,
            $admin_code3,  $latitude,    $longitude,   $accuracy
        ) = split "\t", $line;

        #------ Populate the US Zip Code Table
        $sth_zip->execute( $postal_code, DateTime->now() );

        #------ Populate the Cities Table
        $sth_cit->execute(
            $country_code, $postal_code, $place_name,  $admin_name1,
            $admin_code1,  $admin_name2, $admin_code2, $admin_name3,
            $admin_code3,  $latitude,    $longitude,   $accuracy,
            DateTime->now()
        );

        if ( ( $count++ % 10000 ) == 0 ) {
            say 'Inserted 10000 cities to us_zips and us_cities table.....';
            say "For line $line.....";
        }

    }
    $dbh->commit;
    say 'Populate us_zips and us_cities table is complete! with ' . $count
      . ' records added!';
}

#-------------------------------------------------------------------------------
#  Create a view of all NYC zip codes for the 5 Boroughs
#-------------------------------------------------------------------------------
sub create_view_nyc_zips {
    my $drop_nyc_zips_view = <<"DROP_NYC_ZIPS";
   DROP VIEW if EXISTS nyc_zips;
DROP_NYC_ZIPS

    $dbh->do($drop_nyc_zips_view);

    my $create_nyc_zips_view = <<"CREATE_NYC_ZIPS_VIEW";
    CREATE VIEW IF NOT EXISTS  nyc_zips 
          AS SELECT  us_zips.postal_code
          FROM us_zips INNER JOIN us_cities
          ON  us_zips.postal_code=us_cities.postal_code
          WHERE us_cities.country_code='US'
                 and us_cities.state_code='NY'
                 and us_cities.county_name in ('Bronx', 'Kings', 'New York', 'Queens','Richmond ')
    ORDER BY 1;
CREATE_NYC_ZIPS_VIEW

    $dbh->do($create_nyc_zips_view);

    $dbh->commit;

    say 'Created a new NYC Zip Code view !';
}

#-------------------------------------------------------------------------------
#  Create a view of all NYC places,  counties,  postal_codes for the 5 Boroughs.
#-------------------------------------------------------------------------------
sub create_view_nyc_places {
    my $drop_view_nyc_places = <<"DROP_NYC_PLACES";
   DROP VIEW if EXISTS nyc_places;
DROP_NYC_PLACES

    $dbh->do($drop_view_nyc_places);

    my $create_view_nyc_places = <<"CREATE_VIEW_NYC_PLACES";
    CREATE VIEW IF NOT EXISTS  nyc_places 
          AS SELECT postal_code, place_name, county_name
          FROM us_cities 
          WHERE country_code='US'
            and state_code='NY' 
            and county_name in ('Bronx', 'Kings', 'New York', 'Queens','Richmond ')
    ORDER BY place_name, postal_code, county_name;
CREATE_VIEW_NYC_PLACES

    $dbh->do($create_view_nyc_places);

    $dbh->commit;

    say 'Created a new NYC Places view !';
}

#-------------------------------------------------------------------------------
#  Create a view of all UNIQUE place_name, state_name,state_code, county_name
#-------------------------------------------------------------------------------
sub create_view_places_states {
    my $drop_view_places_states_cty = <<"DROP_PLACE_STATES_CTY";
   DROP VIEW if EXISTS places_states_cty;
DROP_PLACE_STATES_CTY

    $dbh->do($drop_view_places_states_cty);

    my $create_view_places_states_cty = <<"CREATE_VIEW_PLACE_STATES_CTY";
    CREATE VIEW IF NOT EXISTS places_states_cty
       AS SELECT DISTINCT place_name, state_name, state_code,  county_name  
       FROM us_cities 
       WHERE state_name NOT NULL 
         AND state_name !=""
         AND county_name NOT NULL
         AND county_name !=""
    ORDER BY us_cities.place_name, us_cities.state_code, us_cities.postal_code
CREATE_VIEW_PLACE_STATES_CTY

    $dbh->do($create_view_places_states_cty);

    $dbh->commit;

    say 'Created a new place states county view!';
}

