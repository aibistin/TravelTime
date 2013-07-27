use strict;
use warnings;
use ExtUtils::MakeMaker;

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

WriteMakefile(
    NAME         => 'TravelTime',
    AUTHOR       => q{YOUR NAME <aibistin.cionnaith@gmail.com>},
    VERSION_FROM => 'lib/TravelTime.pm',
    ABSTRACT     => 'YOUR APPLICATION ABSTRACT',
    (
        $eumm_version >= 6.3001
        ? ( 'LICENSE' => 'perl' )
        : ()
    ),
    PL_FILES  => {},
    PREREQ_PM => {
        'Test::More'      => 0,
        'YAML'            => 0,
        'Dancer2'         => 0,
        'Plack::Request'  => 0,
        'Config::General' => 0,
        'Modern::Perl'    => 0,
        'autodie'         => 0,
        'Carp' => 0,
        'Dancer2::Plugin::Ajax' => 0,
        'Dancer2::Test' => 0,
        'Data::Dump' => 0,
        'DateTime' => 0,
        'Exporter::NoWork' => 0,
        'ExtUtils::MakeMaker' => 0,
        'File::Find' => 0,
        'File::Spec::Functions' => 0,
        'File::Temp' => 0,
#        'Google::Travel::Matrix' => 0,
        'HTML::Lint' => 0,
        'List::MoreUtils' => 0,
        'List::Util' => 0,
        'Log::Any::Adapter' => 0,
        'Log::Log4perl' => 0,
#        'Mover::Form::Travel::Matrix' => 0,
        'Regexp::Common' => 0,
        'Template' => 0,
        'Test::Exception' => 0,
        'Test::WWW::Mechanize' => 0,
        'Try::Tiny' => 0,
        'utf8::all' => 0,
        'HTML::FormHandler::Moose' => 0, 
        'MooseX::UndefTolerant::Attribute' => 0, 
        'Readonly' => 0, 
        'DBI'      => 0, 
        'DBD::SQLite' => 0, 
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'TravelTime-*' },
);
