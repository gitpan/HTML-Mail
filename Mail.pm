package HTML::Mail;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter MIME::Lite HTML::Parser);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Mail::HTML ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = (
  'all' => [
	  qw(

	  )
  ]
);

our @EXPORT_OK = (@{ $EXPORT_TAGS{'all'} });

our @EXPORT = qw(

);

our $VERSION = '0.01_02';
$VERSION = eval $VERSION;    # see L<perlmodstyle>

# Preloaded methods go here.
use LWP::UserAgent;
use URI;
use HTML::Parser;
use MIME::Lite;
use Carp;

use vars qw($SIMPLE_CID);

sub new {
	my $package = shift;
	my %params  = @_;

	my $self = MIME::Lite->new(@_, Type => 'multipart/alternative');

	if (!(exists($params{'HTML'}) || exists($params{'Text'}))) {
		croak "No HTML or Text parameter send";
	}

	if (exists($params{'HTML'})) {
		$self->{'HTML'} = $params{'HTML'};
	}
	if (exists($params{'Text'})) {
		$self->{'Text'} = $params{'Text'};
	}
	$self->{html_charset} ||= 'iso-8859-1';

	%params = (
	  %params, useragent => 'Mail::HTML',
	  timeout => 60
	);

	$self->{'_ua'} = LWP::UserAgent->new();

	$self->{'_ua'}->agent($params{'useragent'});
	$self->{'_ua'}->timeout($params{'timeout'});

	$self->{'_ua'}->max_size(1024 * 1024);    #One megabyte of content limit (just playing safe)

	my $response = $self->{_ua};

	return bless $self, $package;

}

sub build {
	my $self = shift;

	$self->_parse_html();
	$self->_attach_media();
	$self->_attach_text();
	$self->_build_all();
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

	#clean any possible links that exists
	$self->_reset_links();
	$self->_reset_html();

	eval{
	$self->get($self->{'HTML'});
	};
	if (@_) {
		delete($self->{'_html_base'});
		$self->parse($self->{'HTML'});
	}
	else {
		$self->{'_html_base'} = $self->{'_response'}->base();
		$self->parse($self->{'_response'}->content);
	}
}

#Makes a GET request and returns the content

sub get {
	my $self = shift;
	my $uri  = shift;

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

	return ($self->{'_response'} = $response)->content;
}

sub _add_html {
	my ($self, $tag, $attr, $attrseq) = @_;
	if ($#_ == 1) {
		$self->{'html_content'} .= $tag;    #actually just text
	}
	else {
		$self->{'html_content'} .= "<$tag";
		$self->{'html_content'} .= " $_=\"$attr->{$_}\"" for (@$attrseq);
		$self->{'html_content'} .= ">";
	}
}

sub _get_html {
	my $self = shift;
	return $self->{'html_content'};
}

sub _add_link {
	my $self = shift;
	($#_ == 0) or die "Can only add one link";

	my $uri = URI->new_abs($_[0], $self->{'_html_base'});

	$self->{'links'}->{$uri} ||= $self->_generate_cid();
	return $self->{'links'}->{$uri};
}

sub _get_links {
	my $self = shift;
	return $self->{'links'};
}

sub _reset_links {
	my $self = shift;
	$self->{'links'} = {};
	$self->{'cid'} = 0;
}

sub _reset_html {
	my $self = shift;
	$self->{'html_content'} = '';
}

sub _tag_start {
	my $self = shift;
	my ($tag, $attr, $attrseq) = @_;


	if ($tag eq 'base' and not exists($self->{'_html_base'})) {
		$self->{'_html_base'} = $attr->{'href'};
	}
	
	$self->_tag_filter_link($attr, 'href') if $tag eq 'link';
	$self->_tag_filter_link($attr, 'background');
	$self->_tag_filter_link($attr, 'src');
	$self->_add_html(@_);
}

sub _tag_filter_link {
	my ($self, $attrs, $attr) = @_;
	if (exists($attrs->{$attr})) {
		my $link = $attrs->{$attr};

		$attrs->{$attr} = "cid:" . $self->_add_link($link);
	}
	return;
}

sub _tag_end {
	my $self = shift;
	$self->_add_html(@_);
}

sub _tag_text {
	my $self = shift;
	$self->_add_html(@_);
}

sub _generate_cid {
	my $self = shift;
	return ($SIMPLE_CID ? '': time()) . "_" . $self->{'cid'}++;
}

sub _attach_media {
	my $self = shift;

    my $related = MIME::Lite->new(
        'Type'        => 'multipart/related',
        'Datestamp'   => undef,
        'Disposition' => 'inline',
    );

    my $html_part = MIME::Lite->new(
        'Type'        => 'TEXT',
        'Encoding'    => 'quoted-printable',
        'Data'        => $self->_get_html,
        'Disposition' => 'inline',
        'Datestamp'   => undef,
    );

	$html_part->attr("content-type" => "text/html; charset=$self->{'html_charset'}");

	#attach the html part
	$related->attach($html_part);

	while (my ($link, $cid) = each(%{ $self->_get_links })) {
		$related->attach($self->_get_media($link, $cid));
	}
	$self->{'related_part'} = $related;

	#some cleanup
	delete($self->{'_response'});
	$self->_reset_html;
}

sub _get_media {
	my $self = shift;
	my $link = shift;
	my $cid  = shift;

	$self->get($link);

	my $response = $self->{'_response'};    #holds the response of the previous get

	my $part = MIME::Lite->new(
	  'Encoding'    => 'base64',
	  'Disposition' => 'attachment',
	  'Data'        => $self->{'_response'}->content,
	  'Datestamp'   => undef,
	);

	$part->attr('Content-type' => $self->{'_response'}->content_type);
	$part->attr('Content-ID'   => "<$cid>");

	return $part;
}

sub _attach_text {
	my $self    = shift;
	my $text    = $self->{'Text'};
	my $content = $text;

	#If it fails, Text is the actual text and not an URI
	eval { $content = $self->get($text); };

    my $text_part = new MIME::Lite(
        'Type'        => 'TEXT',
        'Encoding'    => 'quoted-printable',
        'Disposition' => 'inline',
        'Data'        => $content,
        'Datestamp'   => undef,
    );

	return $self->{'text_part'} = $text_part;
}

sub _build_all {
	my $self = shift;

	$self->attach($self->{'text_part'});
	$self->attach($self->{'related_part'});

}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!




=head1 NAME

Mail::HTML - Perl extension for sending emails with embeded HTML and media

=head1 SYNOPSIS

 use HTML::Mail;

 ### initialisation
 my $html_mail = HTML::Mail->new(
 HTML    => 'http://www.cpan.org',
 Text    => 'This is the text representation of the webpage http://www.cpan.org',
 From    => 'me@myhost.org',
 To      => 'you@yourhost.org',
 Subject => 'CPAN webpage');

 ### Dump as string (inherited from MIME::Lite)
 my $sting = $html_mail->as_string();

 ### Send the email (inherited from MIME::Lite)
 $html_mail->send();

=head1 ABSTRACT

 HTML::Mime is supposed to help with the task of sending emails with html amd images (or other media) embeded.
 It uses MIME::Lite for all MIME related things, HTML::Parser to see related files and change the URIs and LWP to retrieve the related files.

=head1 DESCRIPTION



=head2 EXPORT

None by default.

=head1 SEE ALSO

MIME::Lite (this method inherits)

=head1 AUTHOR

Cláudio Valente, E<lt>cvalente@sapo.localE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Cláudio Valente

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

