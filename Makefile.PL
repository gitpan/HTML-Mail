use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'HTML::Mail',
    'VERSION_FROM' => 'lib/HTML/Mail.pm',      # finds $VERSION
    'PREREQ_PM' => { 'MIME::Lite' => 1.0, 'HTML::Parser' => 3.0, 'URI' => 1.0 }, # e.g., Module::Name => 1.1
    ( $] >= 5.005 ?    ## Add these new keywords supported since 5.005
          (    #ABSTRACT_FROM => 'Mail.pm', # retrieve abstract from module
            AUTHOR => 'Cláudio Valente <plank@cpan.org>' ) : () ),
);
