#!/usr/bin/perl
#
# author: gm2bv
# date: 2015/1/14
#

use strict; no strict "refs";
use lib './lib/';
use mdDog;
use Data::Dumper;

my $dog =mdDog->new();
$dog->setup_config();
$dog->login();
$dog->check_auths("all");

if(!$dog->qParam('fid')) {
  $dog->{t}->{error} = "ドキュメントが指定されずにアクセスされました<br>doc_history.cgi<br>Err001";
} else {
  $dog->git_log();
  $dog->set_document_info();
}

$dog->print_page();
exit();