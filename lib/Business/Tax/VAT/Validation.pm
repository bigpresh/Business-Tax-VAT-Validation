package Business::Tax::VAT::Validation;
=pod

=encoding UTF-8

=cut

 ############################################################################
# IT Development software                                                    #
# European VAT number validator Version 1.0.2                                #
# Copyright 2003 Nauwelaerts B  bpgn@cpan.org                                #
# Created 06/08/2003            Last Modified 30/11/2012                     #
 ############################################################################
# COPYRIGHT NOTICE                                                           #
# Copyright 2003 Bernard Nauwelaerts  All Rights Reserved.                   #
#                                                                            #
# THIS SOFTWARE IS RELEASED UNDER THE GNU Public Licence                     #
# Please see COPYING for details                                             #
#                                                                            #
# DISCLAIMER                                                                 #
#  As usual with GNU software, this one is provided as is,                   #
#  WITHOUT ANY WARRANTY, without even the implied warranty of                #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                      #
#                                                                            #
 ############################################################################
# Revision history (dd/mm/yyyy) :                                            #
#                                                                            #
# 1.02   30/11/2012; Fix POD typo; Thanks to Gregor Herrmann                 #
# 1.01   28/11/2012; Fix POD UTF8 Issue; Thanks to Graham Knop               #
# 1.00   25/03/2012; This module now uses the VIES SOAP interface.           #
#                    Add get_informations method                             #
# 0.24   06/03/2012; Fix traderName field required for EL and ES MS          #
#                    Update POST request fields                              #
# 0.23   29/02/2012; Fix regexp in _is_res_ok with multiline regexp          #
#                    (Thanks to Bart Heupers)                                #
# 0.22   04/10/2011; Typo fix in POD error message #2                        #
#                    (Thanks to Martin H. Sluka)                             #
#                    Minor POD fixes (BPGN)                                  #
#                    Fix subs args bug (performance fix) (BPGN)              #
# 0.21   04/08/2009; New error status 19: EU database too busy               #
#                    (Martin H. Sluka)                                       #
# 0.20   18/08/2008; VIES HTML changes: now allowing multiples spaces        #
#                    (Thanks to Simon Williams, Benoît Galy & Raluca Boboia) #
# 0.19   29/04/2008; HU regexp: missing digit "9" added                      #
#                    (Thanks to Simon Williams)                              #
# 0.18   03/01/2008; BE regexp: from transitional 9-digit & 10-digit format  #
#                    to 10-digit new format                                  #
# 0.16   13/07/2007; Allowing spaces in regexps                              #
# 0.15   06/07/2007; Added missing "keys" during $self->{members}            #
#                    constuction                                             #
#                    (Thanks to Dave O.)                                     #
#                    Corrected returned 0-1 error codes inversion            #
#                    Some POD improvements                                   #
# 0.14   05/07/2007; VIES interface changed $baseurl, and POST params were   #
#                    changed to lowercase. Added support for Bulgaria and    #
#                    Romania (thanks to Kaloyan Iliev)                       #
#                    New get_last_error_code method                          #
#                    Updated regexps according to the actual VIES FAQ        #
#                    Some slight documentation improvements                  #
#                    Improved tests: each regexp is tested accordind to FAQ  #
# 0.13   16/01/2007; VIES interface changed "not found" layout               #
#                    (Thanks to Tom Kirkpatrick for this update)             #
# 0.12   10/11/2006; YAML Compliance                                         #
# 0.11   10/11/2006; Minor bug allowing one forbidden character              #
#                    corrected in Belgian regexp                             #
#                     (Thanks to Andy Wardley for this report)               #
#                    + added regular_expressions property                    #
#                      for external testing purposes                         #
# 0.10   20/07/2006; Adding Test::Pod to test suite                          #
# 0.09   20/06/2006; local_check method allows you to test VAT numbers       #
#                    without asking the EU database. Based on regexps.       #
# 0.08   20/06/2006; 9 and 10 digits transitional regexp for Belgium         #
#                    From 31/12/2007, only 10 digits will be valid           #
# 0.07   25/05/2006; Now we use "request" method not "simple request"        #
#                    in order to follow potential redirects                  #
# 0.06   25/05/2006; Changed $baseurl                                        #
#                    (Thanks to Torsten Mueller for this update)             #
# 0.05   19/01/2006; Adding support for proxy settings                       #
#                    (Thanks to Tom Kirkpatrick for this update)             #
# 0.04   01/11/2004; Adding support for error "Member Service Unavailable"   #
# 0.03   01/11/2004; Adding 10 new members.                                  #
#                    (Thanks to Robert Alloway for this update)              #
# 0.02   29/09/2003; Fix alphanumeric VAT numbers rejection                  #
#                    (Thanks to Robert Alloway for the regexps)              #
# 0.01   06/08/2003; Initial release                                         #
#                                                                            #
 ############################################################################
use strict;

BEGIN {
    $Business::Tax::VAT::Validation::VERSION = '1.02';
    use HTTP::Request::Common qw(POST);
    use LWP::UserAgent;
}

=head1 NAME

Business::Tax::VAT::Validation - A class for european VAT numbers validation.

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

This class provides an easy api to check european VAT numbers' syntax, and if they has been registered by the competent authorities.

It asks the EU database (VIES) for this, using its SOAP interface methods. 


=head1 CONSTRUCTOR

=over 4

=item B<new> Class constructor.

    $hvatn=Business::Tax::VAT::Validation->new();
    
    
    If your system is located behind a proxy :
    
    $hvatn=Business::Tax::VAT::Validation->new(-proxy => ['http', 'http://example.com:8001/']);
    
    Note : See LWP::UserAgent for proxy options.

=cut

sub new {
    my ( $class, %arg ) = @_;
    my $self = {
        baseurl      => $arg{baseurl} || 'http://ec.europa.eu/taxation_customs/vies/services/checkVatService',
        error        => '',
        error_code   => 0,
        re           => {
            ### t/01_localcheck.t tests if these regexps accepts all regular VAT numbers, according to VIES FAQ
            AT => 'U[0-9]{8}',
            BE => '0[0-9]{9}',
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
            HU => '[0-9]{8}',
            IE => '[0-9][A-Za-z0-9\+\*][0-9]{5}[A-Za-z]',
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
        },
        proxy        => $arg{-proxy},
        informations => {}
    };
    $self = bless $self, $class;
    $self->{members} = join( '|', keys %{ $self->{re} } );
    $self;
}

=back

=head1 PROPERTIES

=over 4

=item B<member_states> Returns all member states 2-digit codes as array

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
 FI, FR, GB, HU, IE, IT, LU, LT, LV, MT,
 NL, PL, PT, RO, SE, SI, SK

=cut

sub check {
    my ($self, $vatNumber, $countryCode, @other) = @_;    # @other is here for backward compatibility purposes
    return $self->_set_error('You must provide a VAT number') unless $vatNumber;
    $countryCode ||= '';
    ( $vatNumber, $countryCode ) = $self->_format_vatn( $vatNumber, $countryCode );
    if ($vatNumber) {
        my $ua = LWP::UserAgent->new;
        if ( ref $self->{proxy} eq 'ARRAY' ) {
            $ua->proxy( @{ $self->{proxy} } );
        } else {
            $ua->env_proxy;
        }
        $ua->agent( 'Business::Tax::VAT::Validation/'. $Business::Tax::VAT::Validation::VERSION );
        
        my $request = HTTP::Request->new(POST => $self->{baseurl});
        $request->header(SOAPAction => 'http://www.w3.org/2003/05/soap-envelope');
        $request->content(_in_soap_envelope($vatNumber, $countryCode));
        $request->content_type("Content-Type: application/soap+xml; charset=utf-8");
        
        my $response = $ua->request($request);
        
        return $countryCode . '-' . $vatNumber if $self->_is_res_ok( $response->code, $response->decoded_content );
    }
    0;
}

=item B<local_check> - Checks if a VAT number format is valid
    This method is based on regexps only and DOES NOT ask the VIES database
    
    $ok=$hvatn->local_check($VAT, [$member_state]);
    

=cut

sub local_check {
    my ( $self, $vatn, $mscc, @other ) = @_;    # @other is here for backward compatibility purposes
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

=item B<informations> - Returns informations related to the last validated VAT number
    
    %infos=$hvatn->informations();
    

=cut

sub informations {
    my ( $self, $key, @other ) = @_; 
    if ($key) {
        return $self->{informations}{$key} 
    } else {
        return ($self->{informations})    
    }
}

=item B<get_last_error_code> - Returns the last recorded error code

=item B<get_last_error> - Returns the last recorded error

    my $err = $hvatn->get_last_error_code();
    my $txt = $hvatn->get_last_error();

Possible errors are :

=over 4

=item *
 -1  The provided VAT number is valid.

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

### PRIVATE FUNCTIONS ==========================================================
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
    '<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
     SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
     xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
     xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
     xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
     xmlns:xsd="http://www.w3.org/1999/XMLSchema">
     <SOAP-ENV:Body>
     <checkVat xmlns="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
     <countryCode>'.$countryCode.'</countryCode>
     <vatNumber>'.$vatNumber.'</vatNumber>
     </checkVat>
     </SOAP-ENV:Body>
     </SOAP-ENV:Envelope>'
}

sub _is_res_ok {
    my ( $self, $code, $res ) = @_;
    $self->{informations}={};
    $res=~s/[\r\n]/ /g;
    if ($code == 200) {
        if ($res=~m/<valid> *(.*?) *<\/valid>/) {
            my $v = $1;
            if ($v eq 'true' || $v eq '1') {
                if ($res=~m/<name> *(.*?) *<\/name>/) {
                    $self->{informations}{name} = $1
                }
                if ($res=~m/<address> *(.*?) *<\/address>/) {
                    $self->{informations}{address} = $1
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

I<http://ec.europa.eu/taxation_customs/vies/faqvies.do> for the FAQs related to the VIES service.


=head1 FEEDBACK

If you find this module useful, or have any comments, suggestions or improvements, feel free to let me know.


=head1 AUTHOR

Bernard Nauwelaerts <bpgn@cpan.org>


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
Simon Williams, UK2 Limited, United Kingdom & Benoît Galy, Greenacres, France & Raluca Boboia, Evozon, Romania

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

=back

=head1 LICENSE

GPL. Enjoy! See COPYING for further information on the GPL.


=head1 DISCLAIMER

See I<http://ec.europa.eu/taxation_customs/vies/viesdisc.do> to known the limitations of the EU validation service.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

1;
