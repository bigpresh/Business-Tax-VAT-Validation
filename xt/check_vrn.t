#!/usr/bin/env perl

use strict;
use warnings;

use Business::Tax::VAT::Validation;
use Test::More;
use Data::Dumper;

my $hvatn=Business::Tax::VAT::Validation->new();

# Arbitary company registered in Belfast, should be visible to both VIES and
# HMRC
my $vies_belfast = "XI-517356542";
my $hmrc_belfast = "GB-517356542";

# UK mainland company
my $gb_vrn = "356130811";

ok $hvatn->local_check($hmrc_belfast);
ok $hvatn->check($hmrc_belfast);
diag Dumper($hvatn->informations());

# Both the name and address are differently formed in the HMRC and VIES data,
# so we don't attempt to compare.

ok $hvatn->local_check($vies_belfast);
ok $hvatn->check($vies_belfast);
diag Dumper($hvatn->informations());

ok $hvatn->local_check($gb_vrn, "GB");
ok $hvatn->check($gb_vrn, "GB");
diag Dumper($hvatn->informations());

# Cannot tell if a UK company is valid as "NI" without knowing address.
ok $hvatn->local_check($gb_vrn, "XI");
ok !$hvatn->check($gb_vrn, "XI");

done_testing();
