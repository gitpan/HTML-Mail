# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 9;
BEGIN { use_ok('HTML::Mail') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $html_mail = HTML::Mail->new(
  HTML    => '<html><body>Basic Test</body></html>',
  Text    => 'Basic Test',
  From    => 'plank@cpan.org',
  To      => 'plank@cpan.org',
  Subject => 'Test webpage',
);

ok(defined($html_mail), 'Object is defined');
ok(ref($html_mail) eq 'HTML::Mail', 'Object is of the appropriate class');
ok($html_mail->can('build'), 'Object can build message');
ok($html_mail->{'_message'}->isa('MIME::Lite'), 'Object "inherits" from MIME::Lite');
ok($html_mail->{'_message'}->can('send'), 'Object "inherits" send method from MIME::Lite');
ok($html_mail->build, 'Object has built message');
ok($html_mail->as_string, 'Message dumped as string');
ok($html_mail->send, 'Email sent');
