#!/usr/bin/perl
#
# author: gm2bv
# date: 2015/1/27
#

use strict;no strict "refs";
use lib '../lib/';
use mdDogAPI;

my $dog = mdDogAPI->new('api');
$dog->setup_config();
$dog->login();
$dog->check_auths("is_owned", "is_admin");

print "Content-type: application/json; charset=utf-8\n\n";
if( $ENV{'REQUEST_METHOD'} eq 'GET' ){

} elsif( $ENV{'REQUEST_METHOD'} eq 'POST' ) {
    if( $dog->qParam('action') eq 'change_public' ){
        print $dog->document_change_public();
    }
}

exit();
