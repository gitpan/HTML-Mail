package HTML::Mail;

our $VERSION = '0.10';
$VERSION = eval $VERSION;    # see L<perlmodstyle>

# Preloaded methods go here.
use LWP::UserAgent;
require URI;
require HTML::Parser;
require MIME::Lite;

use Carp qw(carp croak);

use strict;
use warnings;

our @ISA = qw(HTML::Parser);

our $SIMPLE_CID;
our $AUTOLOAD;

#see if Data::UUID if present and use cid generation possible
eval{
	require Data::UUID;
};
if($@){
	#UUID not present, use fallback cid generation (should be OK)

*gen_cid = 
	sub{
		my ($self, $uri) = @_;
		return time."_${$}_".(int rand(100_000)).'_'.$self->{'cid'}++;
	};
}else{
	#UUID present, cids will be universally unique

	my $UUID = Data::UUID->new();
*gen_cid = 
	sub{
		my ($self, $uri) = @_;
		return $UUID->to_string($UUID->create);
	};
}

sub new {
	my ($package, %params) = @_;

	my $self = bless {}, $package;
	$self->{'_original_params'} = {};
	$self->{'_cache'}           = {};

	$self->build(%params);

	return $self;
}

#Default LWP::UserAgent

sub _set_default_lwp_ua {
	my $self = shift;
	$self->{'_ua'} ||= LWP::UserAgent->new(
		'agent'   => 'HTML::Mail',
		'timeout' => 60,
	);
	return $self;
}

sub build {
	my ($self, %params) = @_;

	$self->_reset_html;

	%params = (%{$self->{'_original_params'}}, %params);

	if (exists($params{'HTML'})) {
		$self->{'HTML'} = $params{'HTML'};
	}else {
		croak "No HTML parameter send";
	}
	if (exists($params{'Text'})) {
		$self->{'Text'} = $params{'Text'};
	}
	if ($params{'lwp_ua'}) {
		if($params{'lwp_ua'}->isa('LWP::UserAgent')){
			$self->{'_ua'} = $params{'lwp_ua'};
		}else{
			carp "lwp_ua attribute is not a LWP::UserAgent. Using default.";
		}
	}
	
	for my $key qw(inline_css strict_download) {
		$self->{$key} = exists($params{$key}) ? $params{$key} : 1;
	}

	#by default don't attach anything linked
	$self->{'attach_uri'} = sub {return 1;};
	if(exists($params{'attach_uri'})){
		if(ref($params{'attach_uri'}) eq 'CODE'){
			$self->{'attach_uri'} = $params{'attach_uri'};
		}else{
			carp "attach_uri specified but not a subroutine reference. Ignoring and using default.";
		}
	}

	#by default don't attach anything linked
	$self->{'attach_links'} = sub {return 0;};
	if(exists($params{'attach_links'})){
		if(ref($params{'attach_links'}) eq 'CODE'){
			$self->{'attach_links'} = $params{'attach_links'};
		}else{
			carp "attach_links specified but not a subroutine reference. Ignoring and using default.";
		}
	}

	$self->{'html_charset'}    = $params{'html_charset'} || 'iso-8859-15';
	$self->{'text_charset'}    = $params{'html_charset'} || 'iso-8859-15';

	$self->{'_original_params'} =  \%params;
	
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

	my $content = $self->{'_cache'}->{$self->{'HTML'}};
	if(defined($content)){
		$self->parse($content);
		return $self;
	}

	my $response;
	eval { $response = $self->_get($self->{'HTML'}, 1, 1); };
	if ($@ or not ($response and $response->is_success)) {
		delete($self->{'_html_base'});
		if ($self->{'HTML'} =~ /<\s*html.*>/i) {
			#HTML is the content itself
			$self->parse($self->{'HTML'});
		}else {
			#couldn't get HTML so can't do anything
			die $@;
		}
	}
	else {
		$self->{'_html_base'} = $response->base();
		$self->{'_cache'}->{$self->{'HTML'}} = $response->content;
		$self->parse($response->content);
	}
	return $self;
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

#default behaviour: attach all media to email
sub attach_uri{
	my ($self, $url) = @_;
	return $self->{'attach_uri'}->($url);
}

#Makes a GET request and returns the response

sub _get {
	my ($self, $uri, $nowarn, $die) = @_;

	if (!$self || !$self->{'_ua'}) {
		die "User agent not defined";
	}

	if (!$uri) {
		die "uri not defined";
	}

	my $response = $self->{'_ua'}->get($uri);

	if ($response->is_success) {
		return $response;
	}else{
		my $uri2 = $response->request->uri;
		my $error = "Error while making request [GET ". $uri. ($uri eq $uri2 ? "]" : " -> [$uri2]")."\n". $response->status_line;
		if( $self->{'strict_download'} or $die){
			die $error;
		}else{
			unless( $nowarn ){
				carp $error;
			}
			#undef by default
			return;
		}
	}
}

sub _add_html {
	my ($self, $tag, $attr, $attrseq) = @_;
	my $content = \$self->{'html_content'};
	if ($#_ == 1) {
		$$content .= $tag;    #actually just text
		return;
	}

	#special treatment for tags that end with /
	my $empty;
	if($attr->{'/'} && $attr->{'/'} eq '/' && $attrseq){
		pop @$attrseq;
		$empty = 1;
	}

	$$content .= "<$tag";

	if ($attrseq && @$attrseq) {
		$$content .= qq/ $_="$attr->{$_}"/ for (@$attrseq);
	}
	else {
		while (my ($k, $v) = each(%$attr)) {
			$$content .= qq/ $k="$v"/;
		}
	}
	$$content .= " /" if $empty;
	$$content .= ">";
	return $self;
}

sub _get_html {
	return shift->{'html_content'};
}

sub _create_uri {
	my $self = shift;
	defined($_[0]) or die "need a link to create a uri";
	my $base = $self->{'_html_base'};
	if(defined($base)){
		return URI->new_abs($_[0], $base);
	}else{
		return URI->new($_[0]);
	}
}

sub _add_link {
	my ($self, $uri) = @_;

	if(!exists($self->{'links'}->{$uri})){
		my $cid = ($SIMPLE_CID ? $self->{'cid'}++: $self->gen_cid($uri));
		$self->_get_media($uri, $cid);
	}

	if ( exists( $self->{'links'}->{$uri} ) ) {
		return $self->{'links'}->{$uri}->[0];
	}
	else {
		return;
	}
}

sub _get_inline_content {
	my $self = shift;

	my $uri = $self->_create_uri ($_[0]);
	my $response = $self->_get($uri);

	if( defined $response ){
		return $self->{'inline_links'}->{$uri} ||= $self->_get($uri)->content;
	}else{
		return '';
	}
}

sub _get_links {
	return shift->{'links'} || {};;
}

sub _reset_links {
	my $self = shift;
	$self->{'links'} = {};
	$self->{'inline_links'} = {};
	$self->{'cid'} = 0;
	return $self;
}

sub _reset_html {
	shift->{'html_content'} = '';
}

sub _tag_start {
	my $self = shift;
	my ($tag, $attr, $attrseq) = @_;

	if ($tag eq 'base' and not $self->{'_html_base'}) {
		$self->{'_html_base'} = $attr->{'href'};
	}elsif (
		($tag eq 'link') && 
		($attr->{'rel'}  && 
		$attr->{'rel'} eq 'stylesheet') && 
		exists($attr->{'href'})
	){
		if($self->{'inline_css'}){
			return $self->_add_inline_content(@_);
		}else{
			$self->_tag_filter_link($attr, 'href');
		}
	}elsif($tag eq 'a' and defined($attr->{'href'})){
		$attr->{'href'} = $self->_create_uri($attr->{'href'});
	}
	$self->_tag_filter_link($attr, 'background');
	$self->_tag_filter_link($attr, 'src') if ($tag ne 'script');

	#selective attach of linked media
	if(defined($attr->{'href'})){
		if($self->{'attach_links'}->($self->_create_uri($attr->{'href'}))){
			$self->_tag_filter_link($attr, 'href');
		}
	}
	$self->_add_html(@_);
	return $self;
}

sub _add_inline_content{
	my $self = shift;
	my ($tag, $attr) = @_;

	my $link = $attr->{'href'};
	my $content = $self->_get_inline_content($link);

	#try to make easy to generalise in the future
	#javascript and other things may one day be inlined
	if($tag eq 'link' && $attr->{'rel'} eq 'stylesheet'){
		$tag = 'style';
		delete($attr->{'href'});
	}

	$self->_add_html($tag, $attr);
	$self->{'html_content'} .= "\n $content \n</$tag>";
	return $self;
}

sub _tag_filter_link {
	my ($self, $attrs, $attr) = @_;

	if (exists($attrs->{$attr})) {
		my $uri = $self->_create_uri ($attrs->{$attr});

		if($self->attach_uri($uri)){
			my $cid = $self->_add_link($uri);
			if(defined $cid){
				$attrs->{$attr} = "cid:" . $cid;
			}else{
				#just remove content
				$attrs->{$attr} = '';
			}
		}else{
			#place absolute url just in case
			$attrs->{$attr} = $uri->as_string;
		}
	}
	return $self;
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
		#TODO beter tests
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
	return $self;
}

sub _get_media {
	my ( $self, $uri, $cid ) = @_;

	my $response = $self->_get($uri);

	if (    $response
		and $response->can('content')
		and $response->can('content_type') )
	{
		my $part = MIME::Lite->new(
			'Encoding'    => 'base64',
			'Disposition' => 'attachment',
			'Data'        => $response->content,
			'Datestamp'   => undef,
		);

		$part->attr( 'Content-type' => $response->content_type );
		$part->attr( 'Content-ID'   => "<$cid>" );

		$self->{'links'}->{$uri} = [ $cid, $part ];
	}
	return $self;
}

sub _attach_text {
	my $self    = shift;
	my $text    = $self->{'Text'};
	my $content = $self->{'_cache'}->{$text};

	if(!defined($content)){
		eval { $content = $self->_get($text, 1, 1)->content; };
		if(not $content or $@){
			$content = $text;
		}
		$self->{'_cache'}->{$text} = $content;
	}

    my $text_part = new MIME::Lite(
        'Type'        => 'TEXT',
        'Encoding'    => 'quoted-printable',
        'Disposition' => 'inline',
        'Data'        => $content,
        'Datestamp'   => undef,
    );
	$text_part->attr('content-type.charset' => $self->{'text_charset'});

	$self->{'_message'}->attach($text_part);
	return $self;
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
	return $self;
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
	return;
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

=encoding utf-8

=head1 NAME

HTML::Mail - Perl extension for sending emails with embedded  HTML and media

=head1 SYNOPSIS

	use HTML::Mail;

	### initialisation
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

	### Serialise to file for later reuse
	$html_mail->dump_file('/tmp/cpan_mail.data');

	### Restore from file
	my $restored = HTML::Mail->restore_file('/tmp/cpan_mail.data');

=head1 DESCRIPTION

B<HTML::Mail> is supposed to help with the task of sending emails with HTML and images (or other media) embedded or externally linked.
It uses L<MIME::Lite|MIME::Lite> for all MIME related jobs, L<HTML::Parser|HTML::Parser> to find related files and change the URIs and L<LWP::UserAgent|LWP::UserAgent> to retrieve the related files.

Email can be 'multipart/alternative' if both HTML and Text content exist and 'multipart/related' if there is only HTML content.

If all you want is to send text-only email, you probably won't find this module useful at all, or at best a huge overkill.

=head2 Method Summary

=over 4

=item new

Constructor. 
Initialises the object.
See the L<attributes|/Attributes> section

=item build

Regenerates the email. Allows you to change any attributes as in the constructor.
Main difference with C<new> is that it doesn't fetch content that was previously fetched/parsed.

=item lwp_ua

Returns the L<LWP::UserAgent|LWP::UserAgent> object used internally so that it can the customized

=item dump

Serializes the object to a string

=item dump_file

Serializes the object to a file

=item restore

Restores previously serialized object from a string

=item restore_file

Restores previously serialized object from a file

=item gen_cid

Method to generate cids.
Receives $self and the uri to associate the cid to.
If you need to generate your own cids (say, add www.host.com) you should subclass this method.

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

The URL of Text data to send in email. Similar to the HTML attribute. You can also specify the actual text data as a string.

=item From, To, Subject

Inherited from L<MIME::Lite|MIME::Lite>. Sender, Recipient and Subject of the message.

=item html_charset

Charset of the HTML part of the email. Defaults to I<iso-8859-15>.

=item text_charset

Charset of the text part of the email. Defaults to I<iso-8859-15>.

=item lwp_ua

L<LWP::UserAgent|LWP::UserAgent> object used to retrieve documents.
The default agent has a 60 second timeout and sends I<HTML::Mail> as the agent.
See also L<ADVANCED USAGE|/ADVANCED USAGE>.

=item inline_css

A true value specifies that when the HTML uses external css this content be placed in the <style> tag at the header of the document, default value is true.

Don't change the default behaviour unless there is a very strong reason since most email clients won't interpret css unless they are in-lined.

=item attach_uri

Controls which media is attached in the email or referenced to an external source.
See L<Conditional attachment of media|/Conditional attachment of media>

=item attach_links

Controls which links are also included in the email. See L<Linked Media|/Linked Media>.

=item strict_download

Boolean controling whether to die when downloading of media fails. Default True so failing to download media results in a fatal error.

If you are sending email from content with broken images it might be a good idea to turn this on since otherwise the email building procedure will fail.

Use at your own risk.

=back

=head1 ADVANCED USAGE

=head2 LWP::UserAgent options

The C<lwp_ua> method returns the instance of L<LWP::UserAgent|LWP::UserAgent> used to make the request.
Using this method you can change its options to your needs.

	my $ua = LWP::UserAgent->new(%options);
	$html_mail->lwp_ua($ua);

	#or set the options after creation
	$html_mail->lwp_ua->timeout(10);

This is very useful for specifying proxies, cookie parameters, etc.
See L<LWP::UserAgent's manpage|LWP::UserAgent> for all the details.

=head2 Persistence

HTML::Mail objects are designed so that implementing persistence is easy.

The method C<dump> dumps the object as a string. You can store this string in whatever way you wish to and later restore the object with the C<restore> method. There exist also methods C<dump_file> and C<restore_file> that serialize and restore the objects to and from text files.

	### initialisation
	my $html_mail = HTML::Mail->new(
	HTML    => 'http://www.cpan.org',
	Text    => 'This is the text representation of the webpage http://www.cpan.org',
	From    => 'me@myhost.org',
	To      => 'you@yourhost.org',
	Subject => 'CPAN webpage');
	
	### Serialise to string
	my $serial = $html_mail->dump;

	### Restore
	my $hmtl_mail_restored = HTML::Mail->restore($serial);
	
	### Serialise to disk
	### If file exists, its content will be erased
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

The default values are merged in each build meaning that new attributes are sticky. The default value of an attribute is the most recent one specified or the classes default

=head2 Conditional attachment of media

For some reason, there might be some media which should not be attached to the email, but fetched at view time.
The C<attach_uri> method controls this behaviour.
By default all media is attached.
This behaviour can be changed either by inheriting from HTML::Mail and redefining the C<attach_uri> method or by specifying the C<attach_uri> field at construction.

The method's signature is:

  package MyMail;
  use base ('HTML::Mail');

  sub attach_uri{
	my ($self, $uri) = @_;

	return 1; #to attach, 0 to not attach
  }

Where C<$uri> is an L<URI|URI> object. (by overloading it can be treated just like a string in most circumstances)

Or if you prefer

  my $mail = HTML::Mail->new(
    #some parameters
    'attach_uri' => sub {my $uri = shift; return $uri->scheme !~ /^(ftp|file)/i}
  );

will not attach any media fetched via ftp or from the local filesystem.

=head2 Linked Media

attach_links is a subroutine that determines which links will be included in the email. Gets as the argument the C<href> attribute of the tag and is expected to return a C<boolean>, a true return value includes the link a false value doesn't.

	#$html_mail is supposed to have been constructed for the sake of simplicity
	$html_mail->build(attach_links => 
		sub{
			my $link = shift;
			return $link =~ /\.pdf$/
		}
	)

	#This would include all links to pdf documents in the html

By default no links are included.

B<Be aware that a lot of email clients don't cope well with internally linked media>
B<This interface is considered experimental and subject to change, use at your own risk>

=head1 COMPATIBILITY

=head2 Sending email

This module uses L<MIME::Lite|MIME::Lite> to send the emails.
The default behaviour of the C<send> method is to use sendmail, if this is not possible try sending the mail using smtp.
C<$html_mail-E<gt>send('smtp','smtp_server.org')>.

The author has received a report that at least on a Windows 2000 Server system using

  $html_mail->send('smtp','mailhost');

was successful in sending the email.
So far this behaviour has not been reproduced on any other system so use this tip at your own risk.
If you have any information regarding this issue, please contact the author.

Please consult the L<MIME::Lite|MIME::Lite> documentation for further details.

=head2 Suggestions

Try to use only correct HTML, at least it should be well formed.

In-line CSS in HTML documents gives better results with a wider range of email clients.

Don't use Javascript, this module will not include external Javascript, and most clients won't interpret/run the code at all.

This module doesn't support frames/iframes so don't use them for now. Client support for frames is unknown to the author.

=head2 Email Clients

Reports on how clients display emails generated using this module are very welcome.
Successful/unsuccessful stories also welcome.

See the author's email at the end.

=over 4

=item Evolution 1.08

Full compatibility except for some CSS problems.

=item Kmail 1.4.3

HTML OK but usually displays both text and HTML parts with the images as attachments

=item Yahoo webmail (http://mail.yahoo.com)

HTML is shown, not text and all media is OK.

=item Hotmail (http://www.hotmail.com)

Unknown (reports welcome)

=item Outlook Express 6

HTML is shown. When the user prefers text, text content is shown together with a text rendering of the HTML.

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

Considered beta.

=head1  TODO LIST

=over 4

=item Tests

better tests at install time

=back

=head1 AUTHOR

Cláudio Valente, E<lt>plank@cpan.orgE<gt>

=head1 Bug Reporters

I would like to thank the help of:

=over 4

=item Matthew Albright

for bug reporting and submitting a patch

=item Daniel Wijnands

for bug reporting related with email rebuilding

=item Calvin Huang

for reporting a bug with relative links and several limitations regarding frames and iframes

=item Eduardo Correia

for reporting a bug regarding documents with no base URI specified


=item  Marc Logghe

for making suggestions regarding handling of broken links (this suggestion eventually led to the C<strict_download> flag)

=back


=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Cláudio Valente

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut
