# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok('HTML::Mail') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

#for testing purpose
$MIME::Lite::VANILLA = 1;
$HTML::Mail::SIMPLE_CID = 1;

my $dir = `pwd`;
chomp($dir);

my $html_mail = Mail::HTML->new(
  HTML => "file://$dir/teste.html",
  Text => "file://$dir/teste.txt",
  From => 'me@myhost.com',
  To   => 'you@yourhost.com',
  Subject => 'Test webpage',
);

ok(defined($html_mail) ,'Object is defined');
ok(ref($html_mail) eq 'Mail::HTML' ,'Object is of the appropriate class');
ok($html_mail->can('build'), 'Object can build message');
ok($html_mail->can('send'), 'Object inherits send from MIME::Lite');
#ok($html_mail->build, 'Object has built message');
#ok($html_mail->as_string, 'Message dumped as string');
