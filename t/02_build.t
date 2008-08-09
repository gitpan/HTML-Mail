use Test::More tests => 3;
BEGIN { use_ok('HTML::Mail') };

#########################

use Cwd 'abs_path';
use File::Spec::Functions;
		   
my $html_mail = HTML::Mail->new(
	HTML    => "file://" . abs_path(catfile('eg','media', 'test.html')),
	Text    => "file://" . abs_path(catfile('eg','media', 'test.txt')),
	From    => 'plank@cpan.org',
	To      => 'plank@cpan.org',
	Subject => 'Test Build webpage on localdisk',
);

ok(defined($html_mail) ,'Object is defined');
ok($html_mail->build, 'Email was built');
