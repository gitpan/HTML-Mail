# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
BEGIN { use_ok('HTML::Mail') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

#for testing purpose
$MIME::Lite::VANILLA = 1;
$HTML::Mail::SIMPLE_CID = 1;

use Cwd 'abs_path';
		   
my $html_mail = HTML::Mail->new(
	HTML    => "file://" . abs_path('eg/media') . '/test.html',
	Text    => "file://" . abs_path('eg/media') . '/test.txt',
	From    => 'plank@cpan.org',
	To      => 'plank@cpan.org',
	Subject => 'Test Build webpage on localdisk',
);

ok(defined($html_mail) ,'Object is defined');
#ok(check_email($html_mail), 'Sample message is properly built');
ok($html_mail->build, 'Email was built');

TODO:{
	local $TODO = "Not independent of perl version/hashing algorithm";
	ok(check_email($html_mail), 'Rebuilt message is properly built');
};

#this still needs a lot of work to become platform/version independent
sub check_email {
	my $mail  = shift->as_string;
	my $check =
'Content-Transfer-Encoding: binary
Content-Type: multipart/alternative; boundary="_----------=_0"
MIME-Version: 1.0
Subject: Test Build webpage on localdisk
To: plank@cpan.org
From: plank@cpan.org

This is a multi-part message in MIME format.

--_----------=_0
Content-Disposition: inline
Content-Transfer-Encoding: quoted-printable
Content-Type: text/plain; charset="iso-8859-15"
MIME-Version: 1.0

This is the alternative text

HTML::Mail

Thank you for trying the module.

--_----------=_0
Content-Disposition: inline
Content-Transfer-Encoding: binary
Content-Type: multipart/related; boundary="_----------=_1"
MIME-Version: 1.0

This is a multi-part message in MIME format.

--_----------=_1
Content-Disposition: inline
Content-Transfer-Encoding: quoted-printable
Content-Type: text/html; charset="iso-8859-15"
MIME-Version: 1.0

<html>
	<head>
		<meta http-equiv=3D"Content-Type" content=3D"text/html" charset=3D"iso-88=
59-15" /=3D"/">
		<link rel=3D"stylesheet" href=3D"cid:_0" type=3D"text/css" /=3D"/">
		<title>Test HTML</title>
	</head>
	<body>
		<h2 class=3D"red">Entities<br>Aacute &aacute; Euro &euro;</h2>
		<div style=3D"color: green">Inline style GREEN</div>
			<br><img src=3D"cid:_1">
			<br><img src=3D"cid:_2">
			<table border=3D"1" background=3D"cid:_1">
			<tr>
				<td colspan=3D"2">Table</td>
			</tr>
			<tr>
				<td>1</td><td>2</td>
			</tr>
			</table>
			<h1>More text</h1>
	</body>
</html>
--_----------=_1
Content-Disposition: attachment
Content-Id: <_1>
Content-Transfer-Encoding: base64
Content-Type: image/gif
MIME-Version: 1.0

R0lGODlhZABQAMYAAPeaWlJbWGMMC64FBOEAAIgJB0kPDUtJS0ZwPBosDk5kTR5NCiJlBhw8DCR1
BCeNAUt8PiaFAndgUzSHGD2MAkpNUk+iAFhfCkOCMLCnozeKG6y/AHeuADCPDrN9WlpvWUuCBCiV
ADmEIFJ2S2h4ac6/AGxdC4l3CMankhcUEc64qW1zCKaQBt/BAl9SDO7NAYR5dVxRGK6hBPvZAMOo
BEI5DhgcEExCEDErEWZmM2dmU29qQ6V/aNnb3cXGyO21j4x0ZqqJdXhtaXpzcauDaJyEd9+VY+WW
YYZuYIOFitWUaHV5fl5ZWZp5ZcSNaeSUXdOOYbmFYpFwW3toXX6Chr2OcGpsc2ZmZlFTWVhaYpeO
i8yZZuybY7q8v9TV2XF0e1xgZmVpb21wdHp8g4aJjoyPlZmZmb2bhd6dcse8t8zMzLS1uJ2gpaWn
q62wtbepoc6pkOmfbPbcyf////Hv7+Pk59rPx9i1neCsivafYu7Gq/C7l+ykcv///////////yH5
BAEUAH8ALAAAAABkAFAAAAf+gH+Cg4SFhoeIiYqLjI2Oj5CRkol2dnV0c5l0k5ydnoZvbm1tbKVs
a2qYc3Vpn66vi2ZlZGNiYWFgYLdfZG5eXl1ssMOwWrRiYFlYy8xYWVdWX2WjZlrE15NaVF/JWYlM
TGFiS2RlZVTY6Y1JY1bJjVdg0WNJ7Or3iEu4kfJfY/9LhuAb+OfLPknQ/P37IoSgOoNgOgmZN2bJ
FysOrw1552nIuCUgxYjJOAwMlldfvoAEGYbkqysnYalcsrClS0/LiCmsiOxmojt25Mg5JOSLGR+b
YNFc6M6nIS1s3Kzp4qWHmkJJ2kztoqaHl0//APZ0inXMlx07pmRtM4jeNh3+aKlE9RTWbFOygsR8
EZMDB44bNm7ooNKmC5m9O2oEtoEjB5Uy1iSxE3vFG15xYm7UoDGjs4zGSdwksZJjc+cZn2PQnFTX
oGWyMKxYiVHjxenOL2rskL3DxW3cNXKAlBR2ibuYZMNY2WHD9u8ZL27cuuH8dwsbU0ZCqmsLObY6
l+ioykR+TpssVm6weH6ahY4cMth3XhFDjMBHYV17d/ULvH/wPQQoYIB1jAHGFSlU99wLMcSwnnwt
4CAbflRQsQQy+3EylQ9qdOhDF6KwIcssSVRoIhW37HCDfKc1yBmLOExhEyMlUmFWGFkw8UkbUnWx
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
XnEgAAA7

--_----------=_1
Content-Disposition: attachment
Content-Id: <_2>
Content-Transfer-Encoding: base64
Content-Type: image/gif
MIME-Version: 1.0

R0lGODlhMQA4APAAACiVAJmZmSH5BAEKAAAALAAAAAAxADgAQAJxhI+py+0Po5wg2IsvjeHpvWTi
2IEe+ZnqyrZui75c7KKWHNokzvf+DwwKE5khUWfUlYyGEc/JVGJ+UpGvehtamdyu9wsOi8fkJJRr
QyO1SnNavf0Wr6kuzf0OYuuv/fTptyQTCISFN1eWqLjI2OjYUgAAIf4VQ3JlYXRlZCB3aXRoIFRo
ZSBHSU1QADs=

--_----------=_1
Content-Disposition: attachment
Content-Id: <_0>
Content-Transfer-Encoding: base64
Content-Type: text/plain
MIME-Version: 1.0

Ym9keXsKCWZvbnQtc2l6ZTogMTFwdDsKIAlmb250LWZhbWlseTogc2Fucy1zZXJpZjsKfQoKLnJl
ZHsKCWNvbG9yOiByZWQ7Cn0K

--_----------=_1--


--_----------=_0--

';
	#remove date line
	$mail =~ s/\nDate:.+?\n/\n/mg;
	return $mail eq $check;
}
