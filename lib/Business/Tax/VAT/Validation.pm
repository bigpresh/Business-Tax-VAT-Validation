package Business::Tax::VAT::Validation;
=pod

=encoding UTF-8

=cut

 ############################################################################
# Original author:                                                           #
# IT Development software                                                    #
# European VAT number validator                                              #
# Created 06/08/2003                                                         #
#                                                                            #
# Maintainership kindly handed over to David Precious (BIGPRESH) in 2015     #
 ############################################################################
# COPYRIGHT NOTICE                                                           #
# Copyright 2003 Bernard Nauwelaerts  All Rights Reserved.                   #
# Copyright 2015 David Precious       All Rights Reserved.                   #
#                                                                            #
# THIS SOFTWARE IS RELEASED UNDER THE GNU Public Licence version 3           #
# Please see COPYING for details                                             #
#                                                                            #
# DISCLAIMER                                                                 #
#  As usual with GNU software, this one is provided as is,                   #
#  WITHOUT ANY WARRANTY, without even the implied warranty of                #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                      #
#                                                                            #
############################################################################
use strict;
use warnings;

our $VERSION = '1.23';

use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use JSON qw/ decode_json /;

=head1 NAME

Business::Tax::VAT::Validation - Validate EU VAT numbers against VIES/HMRC

=head1 SYNOPSIS

  use Business::Tax::VAT::Validation;

  my $hvatn=Business::Tax::VAT::Validation->new();

  # Check number
  if ($hvatn->check($VAT, [$member_state])){
        print "OK\n";
  } else {
        print $hvatn->get_last_error;
  }

=head1 DESCRIPTION

This class provides an easy API to check European VAT numbers' syntax,
and check if they have been registered by the competent authorities.

It asks the EU database (VIES) for this, using its SOAP API.  Basic checks that
the supplied VAT number fit the expected format for the specified EU member
state are performed first, to avoid unnecessarily sending queries to VIES for
input that could never be valid.

It also supports looking up VAT codes from the United Kingdom by using the
REST API provided by their HMRC.

=head1 CONSTRUCTOR

=over 4

=item B<new> Class constructor.

    $hvatn=Business::Tax::VAT::Validation->new();


    # If your system is located behind a proxy :

    $hvatn=Business::Tax::VAT::Validation->new(-proxy => ['http', 'http://example.com:8001/']);

    # Note : See LWP::UserAgent for proxy options.

=cut

sub new {
    my ( $class, %arg ) = @_;
    my $self = {
        baseurl      => $arg{baseurl} || 'https://ec.europa.eu/taxation_customs/vies/services/checkVatService',
        hmrc_baseurl => $arg{hmrc_baseurl} || 'https://api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/',
        error        => '',
        error_code   => 0,
        response     => '',
        re           => {
            ### t/01_localcheck.t tests if these regexps accepts all regular VAT numbers, according to VIES FAQ
            AT => 'U[0-9]{8}',
            BE => '[01][0-9]{9}',
            BG => '[0-9]{9,10}',
            CY => '[0-9]{8}[A-Za-z]',
            CZ => '[0-9]{8,10}',
            DE => '[0-9]{9}',
            DK => '[0-9]{2} ?[0-9]{2} ?[0-9]{2} ?[0-9]{2}',
            EE => '[0-9]{9}',
            EL => '[0-9]{9}',
            ES => '([A-Za-z0-9][0-9]{7}[A-Za-z0-9])',
            FI => '[0-9]{8}',
            FR => '[A-Za-z0-9]{2} ?[0-9]{9}',
            GB => '([0-9]{3} ?[0-9]{4} ?[0-9]{2}|[0-9]{3} ?[0-9]{4} ?[0-9]{2} ?[0-9]{3}|GD[0-9]{3}|HA[0-9]{3})',
            HR => '[0-9]{11}',
            HU => '[0-9]{8}',
            IE => '[0-9][A-Za-z0-9\+\*][0-9]{5}[A-Za-z]{1,2}',
            IT => '[0-9]{11}',
            LT => '([0-9]{9}|[0-9]{12})',
            LU => '[0-9]{8}',
            LV => '[0-9]{11}',
            MT => '[0-9]{8}',
            NL => '[0-9]{9}B[0-9]{2}',
            PL => '[0-9]{10}',
            PT => '[0-9]{9}',
            RO => '[0-9]{2,10}',
            SE => '[0-9]{12}',
            SI => '[0-9]{8}',
            SK => '[0-9]{10}',
            XI => '([0-9]{3} ?[0-9]{4} ?[0-9]{2}|[0-9]{3} ?[0-9]{4} ?[0-9]{2} ?[0-9]{3}|GD[0-9]{3}|HA[0-9]{3})',
        },
        proxy        => $arg{-proxy},
        information => {}
    };
    $self = bless $self, $class;
    $self->{members} = join( '|', keys %{ $self->{re} } );
    $self;
}

=back

=head1 PROPERTIES

=over 4

=item B<member_states> Returns all supported country codes.

These are ISO 3166-1 alpha-2 country codes with two exceptions. This module
supports VAT codes from all current European Union member states and The United
Kingdom of Great Britain and Northern Ireland.

=over 4

=item C<EL> Greece

Must be used in place of Greece's proper code.

=item C<XI> Northern Ireland

May be used rather than C<GB> for checking a Northern Irish company.

=back

    @ms=$hvatn->member_states;

=cut

sub member_states {
    ( keys %{ $_[0]->{re} } );
}

=item B<regular_expressions> - Returns a hash list containing one regular expression for each country

If you want to test a VAT number format ouside this module, e.g. embedded as javascript in a web form.

    %re=$hvatn->regular_expressions;

returns

    (
    AT      =>  'U[0-9]{8}',
    ...
    SK        =>  '[0-9]{10}',
    );

=cut

sub regular_expressions {
    ( %{ $_[0]->{re} } );
}

=back

=head1 METHODS

=cut

=over 4

=item B<check> - Checks if a VAT number exists in the VIES database

    $ok=$hvatn->check($vatNumber, [$countryCode]);

You may either provide the VAT number under its complete form (e.g. BE-123456789, BE123456789)
or specify the VAT and MSC (vatNumber and countryCode) individually.

Valid MS values are :

 AT, BE, BG, CY, CZ, DE, DK, EE, EL, ES,
 FI, FR, GB, HR, HU, IE, IT, LU, LT, LV,
 MT, NL, PL, PT, RO, SE, SI, SK, XI

=cut

sub check {
    my ($self, $vatNumber, $countryCode, @other) = @_;    # @other is here for backward compatibility purposes
    $self->{information} = {};
    return $self->_set_error('You must provide a VAT number') unless $vatNumber;
    $countryCode ||= '';
    ( $vatNumber, $countryCode ) = $self->_format_vatn( $vatNumber, $countryCode );
    if ($vatNumber) {
        if ($countryCode eq 'GB') {
            return $self->_check_hmrc($vatNumber, $countryCode);
        }
        return $self->_check_vies($vatNumber, $countryCode);
    }
    0;
}

=item B<local_check> - Checks if a VAT number format is valid
    This method is based on regexps only and DOES NOT ask the VIES database

    $ok=$hvatn->local_check($VAT, [$member_state]);


=cut

sub local_check {
    my ( $self, $vatn, $mscc, @other ) = @_;    # @other is here for backward compatibility purposes
    $self->{information} = {};
    return $self->_set_error('You must provide a VAT number') unless $vatn;
    $mscc ||= '';
    ( $vatn, $mscc ) = $self->_format_vatn( $vatn, $mscc );
    if ($vatn) {
        return 1;
    }
    else {
        return 0;
    }
}

=item B<information> - Returns information related to the last checked VAT number

    # Get all available information as a hashref:
    my $info = $hvatn->information();

    # Get a particular key:
    my $address = $hvatn->information('address');

Which information is offered depends on the checker used - for UK VAT numbers,
checked via the HMRC API, C<address> is the only key which will be set.

For EU VAT numbers checked via VIES, you can expect C<name> and C<address>.
This hashref will be reset every time you call check() or local_check()

=cut

sub information {
    my ( $self, $key, @other ) = @_;
    if ($key) {
        return $self->{information}{$key}
    } else {
        return ($self->{information})
    }
}

=item B<get_last_error_code> - Returns the last recorded error code

=item B<get_last_error> - Returns the last recorded error

    my $err = $hvatn->get_last_error_code();
    my $txt = $hvatn->get_last_error();

Possible errors are :

=over 4

=item *
 -1  The provided VAT number is valid (so, no error occurred)

=item *
  0  Unknown MS code : Internal checkup failed (Specified Member State does not exist)

=item *
  1  Invalid VAT number format : Internal checkup failed (bad syntax)

=item *
  2  This VAT number doesn't exist in EU database : distant checkup

=item *
  3  This VAT number contains errors : distant checkup

=item *
 17  Time out connecting to the database : Temporary error when the connection to the database times out

=item *
 18  Member Sevice Unavailable: The EU database is unable to reach the requested member's database.

=item *
 19  The EU database is too busy.

=item *
 20  Connexion to the VIES database failed.

=item *
 21  The VIES interface failed to parse a stream. This error occurs unpredictabely, so you should retry your validation request.

=item *
257  Invalid response, please contact the author of this module. : This normally only happens if this software doesn't recognize any valid pattern into the response document: this generally means that the database interface has been modified, and you'll make the author happy by submitting the returned response !!!

=item *
500  The VIES server encountered an internal server error.
Error 500 : soap:Server TIMEOUT
Error 500 : soap:Server MS_UNAVAILABLE

=back

If error_code > 16,  you should temporarily accept the provided number, and periodically perform new checks until response is OK or error < 17
If error_code > 256, you should temporarily accept the provided number, contact the author, and perform a new check when the software is updated.

=cut

sub get_last_error {
    $_[0]->{error};
}

sub get_last_error_code {
    $_[0]->{error_code};
}

=item B<get_last_response> - Returns the full last response

=cut

sub get_last_response {
    $_[0]->{response};
}

### PRIVATE FUNCTIONS ==========================================================
sub _get_ua {
    my ($self) = @_;
    my $ua = LWP::UserAgent->new;
    if ( ref $self->{proxy} eq 'ARRAY' ) {
        $ua->proxy( @{ $self->{proxy} } );
    } else {
        $ua->env_proxy;
    }
    $ua->agent( 'Business::Tax::VAT::Validation/'. $Business::Tax::VAT::Validation::VERSION );
    return $ua;
}

sub _check_vies {
  my ($self, $vatNumber, $countryCode) = @_;
  my $ua = $self->_get_ua();
  my $request = HTTP::Request->new(POST => $self->{baseurl});
  $request->content(_in_soap_envelope($vatNumber, $countryCode));
  $request->content_type("text/xml; charset=utf-8");

  my $response = $ua->request($request);

  return $countryCode . '-' . $vatNumber if $self->_is_res_ok( $response->code, $response->decoded_content );
}

sub _check_hmrc {
    my ($self, $vatNumber, $countryCode) = @_;
    my $ua = $self->_get_ua();

    my $request = HTTP::Request->new(GET => $self->{hmrc_baseurl}.$vatNumber);
    $request->header(Accept => 'application/vnd.hmrc.1.0+json');
    my $response = $ua->request($request);

    $self->{res} = $response->decoded_content;
    if ($response->code == 200) {
        my $data = decode_json($self->{res});
        $self->{information}->{name} = $data->{target}->{name};
        my $line = 1;
        my $address = "";
        while (defined $data->{target}->{address}->{"line$line"}) {
            $address .= $data->{target}->{address}->{"line$line"}."\n";
            $line++;
        }
        $address .= $data->{target}->{address}->{postcode};
        $address .= "\n".$data->{target}->{address}->{countryCode};
        $self->{information}->{address} = $address;
        $self->_set_error( -1, 'Valid VAT Number');
    }
    elsif ($response->code == 404) {
        return $self->_set_error( 2, 'Invalid VAT Number ('.$vatNumber.')');
    }
    elsif ($response->code == 400) {
        return $self->_set_error( 3, 'VAT number badly formed ('.$vatNumber.')');
    }
    else {
        return $self->_set_error( 500, 'Could not contact HMRC: '.$response->status_line);
    }

    return $countryCode . '-' . $vatNumber;
}

sub _format_vatn {
    my ( $self, $vatn, $mscc ) = @_;
    my $null = '';
    $vatn =~ s/\-/ /g;
    $vatn =~ s/\./ /g;
    $vatn =~ s/\s+/ /g;
    if ( !$mscc && $vatn =~ s/^($self->{members}) ?/$null/e ) {
        $mscc = $1;
    }
    return $self->_set_error( 0, "Unknown MS code" )
      if $mscc !~ m/^($self->{members})$/;
    my $re = $self->{re}{$mscc};
    return $self->_set_error( 1, "Invalid VAT number format" )
      if $vatn !~ m/^$re$/;
    ( $vatn, $mscc );
}

sub _in_soap_envelope {
    my ($vatNumber, $countryCode)=@_;
    return <<EWWSOAP;
<s11:Envelope xmlns:s11='http://schemas.xmlsoap.org/soap/envelope/'>
     <s11:Body>
     <tns1:checkVat xmlns:tns1='urn:ec.europa.eu:taxud:vies:services:checkVat:types'>
     <tns1:countryCode>$countryCode</tns1:countryCode>
     <tns1:vatNumber>$vatNumber</tns1:vatNumber>
     </tns1:checkVat>
     </s11:Body>
     </s11:Envelope>
EWWSOAP
}

sub _is_res_ok {
    my ( $self, $code, $res ) = @_;
    $self->{information}={};
    $res=~s/[\r\n]/ /g;
    $self->{response} = $res;
    if ($code == 200) {
        if ($res=~m/<ns2:valid> *(.*?) *<\/ns2:valid>/) {
            my $v = $1;
            if ($v eq 'true' || $v eq '1') {
                if ($res=~m/<ns2:name> *(.*?) *<\/ns2:name>/) {
                    $self->{information}{name} = $1
                }
                if ($res=~m/<ns2:address> *(.*?) *<\/ns2:address>/) {
                    $self->{information}{address} = $1
                }
                $self->_set_error( -1, 'Valid VAT Number');
                return 1;
            } else {
                return $self->_set_error( 2, 'Invalid VAT Number ('.$v.')');
            }
        } else {
            return $self->_set_error( 257, "Invalid response, please contact the author of this module. " . $res );
        }
    } else {
        if ($res=~m/<faultcode> *(.*?) *<\/faultcode> *<faultstring> *(.*?) *<\/faultstring>/) {
            my $faultcode   = $1;
            my $faultstring = $2;
            if ($faultcode eq 'soap:Server' && $faultstring eq 'TIMEOUT') {
                return $self->_set_error(17, "The VIES server timed out. Please re-submit your request later.")
            } elsif ($faultcode eq 'soap:Server' && $faultstring eq 'MS_UNAVAILABLE') {
                return $self->_set_error(18, "Member State service unavailable. Please re-submit your request later.")
            } elsif ($faultstring=~m/^Couldn't parse stream/) {
        	    return $self->_set_error( 21, "The VIES database failed to parse a stream. Please re-submit your request later." );
            } else {
                return $self->_set_error( $code, $1.' '.$2 )
            }
        } elsif ($res=~m/^Can't connect to/) {
        	return $self->_set_error( 20, "Connexion to the VIES database failed. " . $res );
        } else {
            return $self->_set_error( 257, "Invalid response [".$code."], please contact the author of this module. " . $res );
        }
    }
}

sub _set_error {
    my ( $self, $code, $txt ) = @_;
    $self->{error_code} = $code;
    $self->{error}      = $txt;
    undef;
}

=back

=head1 SEE ALSO

LWP::UserAgent

L<https://ec.europa.eu/taxation_customs/vies/#/faq> for the FAQs related to the VIES service.

L<https://www.api.gov.uk/ch/companies-house> for details of the service provided by the UK's HMRC.

=head1 FEEDBACK

If you find this module useful, or have any comments, suggestions or improvements, feel free to let me know.


=head1 AUTHOR

Original author: Bernard Nauwelaerts <bpgn@cpan.org>

Maintainership since 2015: David Precious (BIGPRESH) <davidp@preshweb.co.uk>


=head1 CREDITS

Many thanks to the following people, actively involved in the development of this software by submitting patches, bug reports, new members regexps, VIES interface changes,... (sorted by last intervention) :

=over 4

=item *
Gregor Herrmann, Debian.

=item *
Graham Knop.

=item *
Bart Heupers, Netherlands.

=item *
Martin H. Sluka, noris network AG, Germany.

=item *
Simon Williams, UK2 Limited, United Kingdom

=item *
Benoît Galy, Greenacres, France

=item *
Raluca Boboia, Evozon, Romania

=item *
Dave O., POBox, U.S.A.

=item *
Kaloyan Iliev, Digital Systems, Bulgaria.

=item *
Tom Kirkpatrick, Virus Bulletin, United Kingdom.

=item *
Andy Wardley, individual, United Kingdom.

=item *
Robert Alloway, Service Centre, United Kingdom.

=item *
Torsten Mueller, Archesoft, Germany

=item *
Dave Lambley (davel), GoDaddy, United Kingdom

item *
Tatu Wikman (tswfi)

=back

=head1 LICENSE

GPL3. Enjoy! See COPYING for further information on the GPL.


=head1 DISCLAIMER

See L<http://ec.europa.eu/taxation_customs/vies/viesdisc.do> to known the limitations of the EU validation service.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

1;
