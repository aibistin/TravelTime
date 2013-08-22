use Test::More;
use strict;
use warnings;
# the order is important
use lib '../lib/';
use_ok 'TravelTime';
use Dancer2::Test;
use Test::LeakTrace;
use Log::Any::Adapter qw/Stdout/;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);


route_exists [GET => '/'], 'a route handler is defined for /';
response_status_is ['GET' => '/'], 200, 'response status is 200 for /';

route_exists [GET => '/travel_time'], 'a route handler is defined for /travel_time';
response_status_is ['GET' => '/travel_time'], 200, 'response status is 200 for /travel_time';

route_exists [GET => '/quick'], 'a route handler is defined for /travel_time';
response_status_is ['GET' => '/quick'], 200, 'response status is 200 for /quick';
route_exists [POST => '/quick'], 'a route handler is defined for POST  /quick';
response_status_is [' POST ' => '/quick'], 200, 'response status is 200 for POST /quick';







#-------------------------------------------------------------------------------
#  Temporary end marker
#-------------------------------------------------------------------------------
done_testing();
__END__
