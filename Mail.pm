package HTML::Mail;

use strict;
use warnings;

our @ISA = qw(HTML::Parser);

our $VERSION = '0.02_00';
$VERSION = eval $VERSION;    # see L<perlmodstyle>

# Preloaded methods go here.
use LWP::UserAgent;
use URI;
use HTML::Parser;
use MIME::Lite;
use Carp qw(carp croak);

use vars qw($SIMPLE_CID $AUTOLOAD);

sub new {
	my ($package, %params) = @_;

	my $self = bless {}, $package;
	$self->{'_original_params'} = \%params;
	$self->build();
	
	return $self;
}

#Default LWP::UserAgent

sub _set_default_lwp_ua {
	my $self = shift;
	$self->{'_ua'} ||= LWP::UserAgent->new(
		'agent'   => 'HTML::Mail',
		'timeout' => 60,
	);
}

sub build {
	my ($self, %params) = @_;

	$self->_reset_html;
	$self->_reset_links;

	%params = (%{$self->{'_original_params'}}, %params);

	if (exists($params{'HTML'})) {
		$self->{'HTML'} = $params{'HTML'};
	}else {
		croak "No HTML parameter send";
	}
	if (exists($params{'Text'})) {
		$self->{'Text'} = $params{'Text'};
	}
	if (exists($params{'lwp_ua'})) {
		if($params{'lwp_ua'}->isa('LWP::UserAgent')){
			$self->{'_ua'} = $params{'lwp_ua'};
		}else{
			carp "lwp_ua attribute is not a LWP::UserAgent";
		}
	}

	$self->{'html_charset'} = $params{'html_charset'} || 'iso-8859-15';
	$self->{'text_charset'} = $params{'html_charset'} || 'iso-8859-15';
	$self->_set_default_lwp_ua();
	
	$self->{'_message'} = MIME::Lite->new(
		%params,
		Type => $self->{'Text'} ? 
			'multipart/alternative' : 
			'multipart/related',
	);

	$self->_parse_html;
	if($self->{'Text'}) {
		$self->_attach_text;
	}
	$self->_attach_media;

	return $self;
}

sub _parse_html {
	my $self = shift;

	#set up the HTML parser
	$self->init(
		api_version => 3,
		start_h     => [\&_tag_start, 'self, tag, attr, attrseq'],
		end_h       => [\&_tag_end, 'self, tag, attr, attrseq'],
		text_h      => [\&_tag_end, 'self, text'],
	);

	my $response;
	eval { $response = $self->_get($self->{'HTML'}); };
	if (@_ or not ($response and $response->is_success)) {
		delete($self->{'_html_base'});
		if ($self->{'HTML'} =~ /html/i) {
			$self->parse($self->{'HTML'});
		}else {
			die @_;
		}
	}
	else {
		$self->{'_html_base'} = $response->base();
		$self->parse($response->content);
	}
}

#Return LWP::UserAgent used to make requests
#Allows user to fine tune options

sub lwp_ua{
	my ($self, $ua) = @_;
	
	if (ref($ua) && $ua->isa('LWP::UserAgent')){
		$self->{'_ua'} = $ua;
	}
	return $self->{'_ua'};
}

#Makes a GET request and returns the content

sub _get {
	my ($self, $uri) = @_;

	if (!$self || !$self->{'_ua'}) {
		die "User agent not defined";
	}

	if (!$uri) {
		die "uri not defined";
	}

	my $response = $self->{'_ua'}->get($uri);

	if (!$response->is_success) {
		croak "Error while making request [", $response->request->uri, "]\n", $response->status_line;
	}

	return $response;
}

sub _add_html {
	my ($self, $tag, $attr, $attrseq) = @_;
	my $content = \$self->{'html_content'};
	if ($#_ == 1) {
		$$content .= $tag;    #actually just text
	}
	else {
		$$content .= "<$tag";
		$$content .= " $_=\"$attr->{$_}\"" for (@$attrseq);
		$$content .= ">";
	}
}

sub _get_html {
	return shift->{'html_content'};
}

sub _add_link {
	my $self = shift;
	($#_ == 0) or die "Can only add one link";

	my $uri = URI->new_abs($_[0], $self->{'_html_base'});

	if(!exists($self->{'links'}->{$uri}->[0])){
		my $cid = ($SIMPLE_CID ? '': int rand(10000)) . "_" . $self->{'cid'}++;
		$self->_get_media($uri, $cid);
	}

	return $self->{'links'}->{$uri}->[0];
}

sub _get_links {
	return shift->{'links'};
}

sub _reset_links {
	my $self = shift;
	$self->{'links'} = {};
	$self->{'cid'} = 0;
}

sub _reset_html {
	shift->{'html_content'} = '';
}

sub _tag_start {
	my $self = shift;
	my ($tag, $attr, $attrseq) = @_;

	if ($tag eq 'base' and not exists($self->{'_html_base'})) {
		$self->{'_html_base'} = $attr->{'href'};
	}
	if (($tag eq 'link') && (exists($attr->{'rel'}) && $attr->{'rel'} eq 'stylesheet')){
		$self->_tag_filter_link($attr, 'href');
	}
	$self->_tag_filter_link($attr, 'background');
	$self->_tag_filter_link($attr, 'src') if ($tag ne 'script');
	$self->_add_html(@_);
}

sub _tag_filter_link {
	my ($self, $attrs, $attr) = @_;
	if (exists($attrs->{$attr})) {
		my $link = $attrs->{$attr};
		$attrs->{$attr} = "cid:" . $self->_add_link($link);
	}
}

sub _tag_end {
	shift->_add_html(@_);
}

sub _tag_text {
	shift->_add_html(@_);
}

sub _attach_media {
	my $self = shift;

    my $related;
	
	if($self->{'Text'}) {
		$related = MIME::Lite->new(
			'Type'        => 'multipart/related',
			'Datestamp'   => undef,
			'Disposition' => 'inline',
		);
	}else{
		$related = $self->{'_message'};
	}

    my $html_part = MIME::Lite->new(
        'Type'        => 'text/html',
        'Encoding'    => 'quoted-printable',
        'Data'        => $self->_get_html,
        'Disposition' => 'inline',
        'Datestamp'   => undef,
    );

	$html_part->attr('content-type.charset' => $self->{'html_charset'});

	#attach the html part
	$related->attach($html_part);

	if($SIMPLE_CID){
		#needs to be sorted in order to run the build tests
		#otherwise the order depends on the hashing function and threrefore on perl's version
		my %links = %{ $self->_get_links };
		for (sort keys %links) {
			$related->attach($links{$_}->[1]);
		}
	}else{
		while ( my ( $link, $media ) = each( %{ $self->_get_links } ) ) {
			$related->attach( $media->[1] );
		}
	}

	
	if($self->{'Text'}){
		$self->{'_message'}->attach($related);
	}
}

sub _get_media {
	my ($self, $uri, $cid) = @_;

	my $response = $self->_get($uri);

	my $part = MIME::Lite->new(
	  'Encoding'    => 'base64',
	  'Disposition' => 'attachment',
	  'Data'        => $response->content,
	  'Datestamp'   => undef,
	);

	$part->attr('Content-type' => $response->content_type);
	$part->attr('Content-ID'   => "<$cid>");

	$self->{'links'}->{$uri} = [$cid, $part];
}

sub _attach_text {
	my $self    = shift;
	my $text    = $self->{'Text'};
	my $content = $text;

	#If it fails, Text is the actual text and not an URI
	eval { $content = $self->_get($text)->content; };

    my $text_part = new MIME::Lite(
        'Type'        => 'TEXT',
        'Encoding'    => 'quoted-printable',
        'Disposition' => 'inline',
        'Data'        => $content,
        'Datestamp'   => undef,
    );
	$text_part->attr('content-type.charset' => $self->{'text_charset'});

	$self->{'_message'}->attach($text_part);
}

sub dump {
	require Data::Dumper;
	
	my $self = shift;
	return Data::Dumper->Dump([$self], [qw(html_mail_dump)]);
}

sub dump_file {
	my ($self, $fname) = @_;
	my $file;
	
	open $file, ">$fname" or croak "Error openning file $fname for writting.\n$!";
	print $file $self->dump;
}

sub restore {
	my (undef, $data) = @_;

	my $html_mail_dump;

	eval "$data";
	return $html_mail_dump;
}

sub restore_file {
	my ($package, $fname) = @_;
	my $file;
	
	open $file, "<$fname" or croak "Error openning file $fname for reading.\n$!";
	{
		local $/;
		my $data = <$file>;
		return $package->restore($data);
	}
}

sub AUTOLOAD {
	my $self = shift;
	$AUTOLOAD =~ s/.*:://;
	if($self->{'_message'} && $self->{'_message'}->can($AUTOLOAD)){
		return $self->{'_message'}->$AUTOLOAD(@_);
	}
}



1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

HTML::Mail - Perl extension for sending emails with embedded  HTML and media

=head1 SYNOPSIS

	use HTML::Mail;

	### initialization
	my $html_mail = HTML::Mail->new(
		HTML    => 'http://www.cpan.org',
		Text    => 'This is the text representation of the webpage http://www.cpan.org',
		From    => 'me@myhost.org',
		To      => 'you@yourhost.org',
		Subject => 'CPAN webpage');
	
	### Send the email ("inherited" from MIME::Lite)
	$html_mail->send();

	#### Remove text representation
	$html_mail->set_Text();
	
	### Rebuild the message and send
	$html_mail->build->send;

	### Serialize to file for later reuse
	$html_mail->dump_file('/tmp/cpan_mail.data');

	### Restore from file
	my $retored = HTML::Mail->restore_file('/tmp/cpan_mail.data');

=head1 DESCRIPTION

B<HTML::Mime> is supposed to help with the task of sending emails with HTML and images (or other media) embedded .
It uses L<MIME::Lite|MIME::Lite> for all MIME related jobs, L<HTML::Parser|HTML::Parser> to find related files and change the URIs and L<LWP::UserAgent|LWP::UserAgent> to retrieve the related files.

Email can be 'multipart/alternative' if both HTML and Text content exist and 'multipart/related' if there is only HTML content.

=head2 Method Summary

=over 4

=item new

Constructor. 
Initializes the object.
See the L<attributes|/Attributes> section

=item build

Regenerates the email. Allows you to change any attributes as in the constructor.
Main difference with C<new> is that it doesn't fetch content that was previously fetched/parsed.

=item lwp_ua

Returns the L<LWP::UserAgent|LWP::UserAgent> object used internally

=item dump

Serializes the object to a string

=item dump_file

Serializes the object to a file

=item restore

Restores previously serialized object

=item restore_file

Restores previously serialized object fom a file

=back

=head2 Attributes

All attributes are B<case sensitive>.

	my $html_mail = HTML::Mail->new(attribute => value);

	$html_mail->build(attribute => value);

Constructor supports these attributes:

=over 4

=item HTML [URI or STRING]

The URL of HTML data to send in email.
Most common URLs are either F<http://www.site.org> or F<file:///home/user/page.html>

If you prefer, you can use it to specify the actual HTML data as a string 

	HTML=>'<html><body><h1>Welcome to HTML::Mail</h1></body></html>';

=item Text [URI or STRING]

The URL of Text data to send in email. Similar to the HTML attribute.

=item From, To, Subject

Inherited from L<MIME::Lite|MIME::Lite>. Sender, Recipient and Subject of the message.

=item html_charset

Charset of the HTML part of the email. Defaults to I<iso-8859-15>.

=item text_charset

Charset of the text part of the email. Defaults to I<iso-8859-15>.

=item lwp_ua

L<LWP::UserAgent|LWP::UserAgent> object used to retrieve documents

=back

=head1 ADVANCED USAGE

=head2 LWP::UserAgent options

The C<lwp_ua> method returns the instance of L<LWP::UserAgent|LWP::UserAgent> used to make the request.
Using this method you can change it's options to your needs.

	my $ua = LWP::UserAgent->new(%options);
	$html_mail->lwp_ua($ua);

	#or set the options after creation
	$html_mail->lwp_ua->timeout(10);

This is very useful for specifying proxies, cookie parameters, etc.
See L<LWP::UserAgent|LWP::UserAgent's manpage> for all the details.

=head2 Persistence

HTML::Mail objects are designed so that implementing persistence is easy.

The method C<dump> dumps the object as a string. You can store this string in whatever way you wish to and later restore the object with the C<restore> method. There exist also methods C<dump_file> and C<restore_file> that serialize and restore the objects to and from text files.

	### initialization
	my $html_mail = HTML::Mail->new(
	HTML    => 'http://www.cpan.org',
	Text    => 'This is the text representation of the webpage http://www.cpan.org',
	From    => 'me@myhost.org',
	To      => 'you@yourhost.org',
	Subject => 'CPAN webpage');
	
	### Serialize to string
	my $serialized = $html_mail->dump;

	### Restore
	my $hmtl_mail_restored = HTML::Mail->restore($serialized);
	
	### Serialize to disk
	### If file exists, it's content will be erased
	my $file = '/tmp/stored_html_mail.data';
	$html_mail->dump_file($file);

	### Restore from file
	my $hmtl_mail_restored = HTML::Mail->restore_file($file);
	

None of these methods are meant for speed.
Be also careful when restoring data that you don't trust since these methods basically use C<eval> to restore the objects.

All relevant data is stored, so you can send a restored email without fetching content again, or doing any HTML parsing if it was done before storing it.

=head2 Rebuilding emails

As of version  0.02_00 the job of reusing an object to send several emails is optimized.
This is mainly due to the fact that if the HTML content is changed, media that was included on the previous build will no longer be fetched and processed. However if there is new media referred to by the new HTML content, it will be fetched and made available for next builds.

This is particular useful for building customizable email campaigns, say putting the customer's name in the content. 

The parsing of the HTML content is always done.

	$html_mail->build(attribute => value)

regenerates the email. The attributes and values are the same as the ones in the C<new> method.

=head1 COMPATIBILITY

=head2 Suggestions

Try to use only correct HTML, at least it should be well formed.

Inline CSS in HTML documents gives better results with a wider range of email clients.

Try not to use Javascript, email clients don't usually support it very well and it's usually turned off for security reasons.

=head2 Email Clients

Reports on how clients display emails generated using this module are very welcome.
Successfull/unsuccessful stories also welcome.

See the author's email at the end.

=over 4

=item Evolution 1.08

Full compatibility except for some CSS problems.

=item Kmail 1.4.3

HTML ok but usually displays both text and HTML parts with the images as attachments

=item Yahoo webmmail (http://mail.yahoo.com)

HTML is shown, not text and all media is ok.

=item Hotmail (http://www.hotmail.com)

Unknown (reports welcome)

=item Outlook

Unknown (reports welcome)

=item Eudora

Unknown (reports welcome)

=back

=head1 EXPORT

None.

=head1 SEE ALSO

L<MIME::Lite|MIME::Lite> (this module "inherits" from it)

L<HTML::Parser|HTML::Parser> (used in this module to parse HTML)

L<LWP::UserAgent|LWP::UserAgent> (used to fetch content)

The F<eg> directory for some examples on how to use the package

=head1 DEVELOPMENT STATUS

Now considered alpha.

=head1  TODO LIST

=over 4

=item CSS/Javascript 

optionally inlined

=item Tests

better tests at install time

=back

=head1 AUTHOR

Cláudio Valente, E<lt>ClaudioV@technologist.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Cláudio Valente

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut
