use ExtUtils::MakeMaker;
use File::Spec::Functions;

use strict;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'HTML::Mail',
    'VERSION_FROM' => 'lib/HTML/Mail.pm',      # finds $VERSION
    'PREREQ_PM' => {
		'MIME::Lite'     => 1.0,
		'HTML::Parser'   => 3.0,
		'URI'            => 1.0,
		'LWP::UserAgent' => 2.0,
		#'Data::UUID' => 0, #This is optional, I recommend installing Data::UUID, but if not present, a simple cid generation will be provided
	},
    ( $] >= 5.005 ?    ## Add these new keywords supported since 5.005
          (    #ABSTRACT_FROM => 'Mail.pm', # retrieve abstract from module
            AUTHOR => 'Cláudio Valente <plank@cpan.org>' ) : () ),
);

eval{
	require Data::UUID;
};
if($@){
	print STDERR "\n\n**********\nData::UUID not present, It's recommended (though not mandatory) to install it\n**********\n\n";
}

my $email='plank@cpan.org';
for (@ARGV){
	if(not defined $email){
		$email = $_;
	}elsif($_ eq 'EMAIL'){
		$email=undef;
	}elsif($_ eq 'NOEMAIL'){
		$email=0;
	}
}
my $fname = catfile(qw(t email));

if($email){
	open(my $file, '>', $fname);
	print $file $email;
	close($file);
}else{
	unlink($fname);
}
