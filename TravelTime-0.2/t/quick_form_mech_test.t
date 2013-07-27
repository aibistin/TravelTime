#!/usr/bin/perl
use Modern::Perl;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/ all any/;
use Carp qw /confess/;
use Data::Dump qw/dump/;
use Try::Tiny;

use Log::Any::Adapter qw/Stdout/;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

#Log::Log4perl->easy_init($DEBUG);

use Test::More;
use Test::Exception;
use Test::WWW::Mechanize;
use HTML::Lint;

my ( $test_moose_stuff, $test_get_distances );

#-------------------------------------------------------------------------------
#  And The Star Is.....
#-------------------------------------------------------------------------------
use lib '../lib/';
use TravelTime;

#-------------------------------------------------------------------------------
#  Constants
#-------------------------------------------------------------------------------
my $LOCALHOST                = q{localhost:5000};
my $TRAVEL_TIME_START        = q{/travel_time};
my $TRAVEL_TIME_QUICK        = q{/quick};
my $MIN_ADDR_FIELD_LEN       = 3;
my $MIN_ADDR_STATE_FIELD_LEN = 2;
my $MAX_ADDR_FIELD_LEN       = 80;
my $BASE                     = $LOCALHOST;

my $lint = HTML::Lint->new( only_types => HTML::Lint::Error::STRUCTURE );
my $mech = Test::WWW::Mechanize->new( autolint => $lint );

$mech->get_ok($BASE . $TRAVEL_TIME_QUICK);
$mech->base_is( $BASE, 'Proper <BASE HREF>' );
$mech->title_is(
    'Mover Travel Time Calculator', "Make sure we're on the
    Quick Travel Time Calculator Page"
);
$mech->content_like( qr/truck travel time/, 'truck travel time line is there' );
$mech->text_contains( 'CarryOnMoving',   'CarryOnMoving heading is there' );
$mech->text_contains( 'Start Location',  'Start Location is on the page' );
$mech->text_contains( 'End Location',    'End Location is on the page' );
$mech->text_contains( 'Get Travel Time', 'Get Travel Time button is there' );
$mech->text_contains( 'Moving Management',
    'Link to Moving Management is there' );
$mech->text_contains( 'Dancer2',      'Link to Dancer2 is there' );
$mech->text_contains( 'Bootstrap',    'Link to Bootstrap is there' );
$mech->text_contains( 'Austin Kenny', 'I\'m there!!!' );

$mech->content_like( qr/truck travel time/, 'truck travel time line is there' );
$mech->content_like( qr/(cpan|perl)\.org/,  'Link to perl.org or CPAN' );
