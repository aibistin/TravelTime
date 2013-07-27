#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: city-state-zip.pl
#
#        USAGE: ./city-state-zip.pl
#
#  DESCRIPTION: Create sorted files of :
#      city_state_statecode_zip.txt
#      city_state_statecode.txt (unique)
#      city_statecode_zip.txt
#      statecode_city_zip.txt
#      statecode_state_city.txt
#      zip_city_statecode.txt   (unique) 
#      city_state_zip.txt
#      city_state.txt (unique)
#     From an input file "US.txt" obtained from the genames.org website
#
#      OPTIONS: ---
# REQUIREMENTS: --- US.txt from http://www.geonames.org
#         BUGS: ---
#        NOTES: --- Remove FM state eg Chuuk (Micronesia)
#                   Remove APO (Army post office)
#                   Remove FPO (Fleet post office)
#                   GU, MH, PW, MP
#                   Maybe Remove Hawii and Alaska
#       AUTHOR: Austin Kenny (), aibistin.cionnaith@gmail.com
# ORGANIZATION: Carry On Coding
#      VERSION: 1.0
#      CREATED: 06/23/2013 03:37:51 PM
#     REVISION: ---
#===============================================================================
use Modern::Perl qw/2012/;
use strict;
use warnings;
use autodie;
use utf8;
use Data::Dump qw/dump/;

#use diagnostics -verbose;

#-------------------------------------------------------------------------------
#  Globals
#-------------------------------------------------------------------------------
my $in_file = q/US.txt/;

#------ Output Arrays
my (
    @city_state_statecode_zip, @city_state_statecode,
    @city_statecode_zip,       @statecode_city_zip,
    @statecode_state_city,     @zip_city_statecode,
    @city_state_county, @city_state_zip, @city_state
);

open my $us_data, '<', $in_file
  or die 'Cannot open the input file, ' . $in_file . ',  because: ' . $!;

while ( my $line = <$us_data> ) {
    chomp($line);

    #------ place name : maspeth ,  admin_name1 : New York,  admin_code1 : NY,
    #      admin_name2 : Queens:  admin_code2 : 081
    # Note: Manhattan admin_name2 New York
    # Note: Bronx place_name Bronx
    # Note: Bronx admin_name2 Bronx
    # Note: Brooklyn place_name Brooklyn
    # Note: Brooklyn admin_name2 Kings
    # Note: Staten Island place_name Staten Island
    # Note: Staten Island admin_name2 Richmond
    next if  ($line =~ /\t(APO|FPO|FM|GU|MH|PW|MP)\t/);
    my (
        $country_code, $postal_code, $place_name,  $admin_name1,
        $admin_code1,  $admin_name2, $admin_code2, $admin_name3,
        $admin_code3,  $latitude,    $longitude,   $accuracy
    ) = split "\t", $line ;

    say 'The line data is : '
      . $country_code . ' '
      . $postal_code . ' '
      . $place_name . ' '
      . $admin_name1 . ' '
      . $admin_code1 . ' '
      . $admin_name2 . ' '
      . $admin_code2
      if ( $line =~ /11378/i );

    push @city_state_statecode_zip,
      [ $place_name, $admin_name1, $admin_code1, $postal_code ];

    push @city_statecode_zip,   [ $place_name,  $admin_code1, $postal_code ];
    push @city_state_statecode, [ $place_name,  $admin_name1, $admin_code1 ];
    push @statecode_city_zip,   [ $admin_code1, $place_name,  $postal_code ];

    push @statecode_state_city, [ $admin_code1, $admin_name1, $place_name ];

    push @zip_city_statecode, [ $postal_code, $place_name,  $admin_code1 ];
    push @city_state_county, [ $place_name, $admin_name1,$admin_name2 ];
    push @city_state_zip,     [ $place_name,  $admin_name1, $postal_code ];
    push @city_state,         [ $place_name,  $admin_name1 ];
}

#------ Remove duplicate cities
my %have;

@city_state_statecode_zip =
  sort { $a->[0] cmp $b->[0] || $a->[2] cmp $b->[2] || $a->[3] <=> $b->[3] }
  @city_state_statecode_zip;
%have = ();
@city_state_statecode =
 grep { not $have{ $_->[0].$_->[2] }++ }
  sort { $a->[0] cmp $b->[0] || $a->[2] cmp $b->[2] } @city_state_statecode;
@city_statecode_zip =
  sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $a->[2] <=> $b->[2] }
  @city_statecode_zip;
@statecode_city_zip =
  sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $a->[2] <=> $b->[2] }
  @statecode_city_zip;
%have = ();
@statecode_state_city =
 grep { not $have{ $_->[0].$_->[2] }++ }
  sort { $a->[0] cmp $b->[0] || $a->[2] cmp $b->[2] } @statecode_state_city;
@zip_city_statecode =
  sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] <=> $b->[2] }
  @zip_city_statecode;
@city_state_county = grep { not $have{ $_->[0].$_->[1] }++ }
  sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] }
  @city_state_county;
@city_state_zip =
  sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $a->[2] <=> $b->[2] }
  @city_state_zip;
%have = ();
@city_state = grep { not $have{ $_->[0].$_->[1] }++ }
sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @city_state;

my @outfiles = (
    qw/
      city_state_statecode_zip.txt
      city_state_statecode.txt
      city_statecode_zip.txt
      statecode_city_zip.txt
      statecode_state_city.txt
      zip_city_statecode.txt
      city_state_county.txt
      city_state_zip.txt
      city_state.txt
      /
);

foreach my $array (
    \@city_state_statecode_zip, \@city_state_statecode,
    \@city_statecode_zip,       \@statecode_city_zip,
    \@statecode_state_city,     \@zip_city_statecode,
    \@city_state_county, \@city_state_zip,  \@city_state
  )
{

    open my $outfile, '>', shift @outfiles;
    foreach my $outline (@$array) {
        print $outfile join ',', @{$outline};
        print $outfile "\n";
    }
    close $outfile;
}

