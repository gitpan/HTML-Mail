# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN { use_ok('HTML::Mail') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $html_mail = HTML::Mail->new(
  HTML    => '<html><body><h1>Test Persistence</h1></body></html>',
  Text    => 'Test Persistence',
  From    => 'plank@cpan.org',
  To      => 'plank@cpan.org',
  Subject => 'Test Persistence',
);

my $serial;
ok($serial = $html_mail->dump ,'Object was serialized');
ok(HTML::Mail->restore($serial) ,'Object restored from serialization');
