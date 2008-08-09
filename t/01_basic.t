use Test::More tests => 10;
BEGIN { use_ok('HTML::Mail') };

use File::Spec::Functions;

#########################

my $email_file = catfile(qw(t email));
my $default_email = 'plank@sapo.pt';
my $email = $default_email;

if( -e $email_file ){
	open(my $file, '<', $email_file);
	$email = <$file>;
	chomp($email);
}else{
	$email = undef;
}
my $html_mail;

ok($html_mail = HTML::Mail->new(
  HTML    => '<html><body>Basic Test</body></html>',
  Text    => 'Basic Test',
  From    => $email || $default_email,
  To      => $email || $default_email,
  Subject => 'Test webpage',
), 'Constuction of object' );

ok(defined($html_mail), 'Object is defined');
ok($html_mail->isa('HTML::Mail'), 'Object is of the appropriate class');
ok($html_mail->can('build'), 'Object can build message');
ok($html_mail->{'_message'}->isa('MIME::Lite'), 'Object "inherits" from MIME::Lite');
ok($html_mail->{'_message'}->can('send'), 'Object "inherits" send method from MIME::Lite');
ok($html_mail->build, 'Object has built message');
ok($html_mail->as_string, 'Message dumped as string');

TODO: {
	local $TODO = "This is just way too system specific to get right everywhere.";
	todo_skip "User doesn't want to test this", 1 if not defined($email);
	ok(test_send(), 'Email sent');
}

sub test_send{
eval{
	$html_mail->send;
};
if($@){
	$html_mail->send('smtp','cpan.mx.develooper.com');
	}
}
