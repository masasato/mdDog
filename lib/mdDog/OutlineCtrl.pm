package OutlineCtrl;

# --------------------------------------------------------------------
# @Author Yoshiaki Hori
# @copyright 2014 Yoshiaki Hori gm2bv2001@gmail.com
#
# This file is part of mdDog.
#
# mdDog is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# mdDog is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
# --------------------------------------------------------------------

use strict; no strict "refs"; no strict "subs";
use base mdDog;
use constant A_DIV => "DIVIDE";
use constant A_INDT => "INDENT";

############################################################
# outline.datを編集する
#  フォーマット
#  [要素No]:[DIVIDE|INDENT|SIZEUP|SIZEDOWN|CENTER]:[COMMENT]
#
# @param1: 作業ディレクトリ
#
sub new {
  my $pkg = shift;
  my $workdir = shift;

  my $hash = {
    filename => "outline.dat",
    workdir  => $workdir,
  };

  my $filepath = "$hash->{workdir}/$hash->{filename}";
  unless( -f $filepath ){
    open my $hF, ">", $filepath || die "Create Error!. $filepath";
    close($hF);
  }

  return bless $hash, $pkg;
}

####################################################################
# ハッシュをクリアしてデータファイルから解析して新たに生成
#
sub init {
  my $self = shift;
  my $datpath = "$self->{workdir}/$self->{filename}";

  foreach ('DIVIDE','INDENT','SIZEUP','SIZEDOWN','CENTER') {
    $self->{$_} = undef;
  }
  return unless(-f $datpath);

  my $document;
  my $pos = 0;
  open my $hF, '<', $datpath || die "can't open $datpath";
  while(my $length = sysread $hF, $document, 1024, $pos) {
    $pos += $length;
  }
  close $hF;

  foreach(split(/\n/, $document)){
    my @cols = split(/:/, $_);
    my $num = ${cols}[0];
    my $action = ${cols}[1];
    my $comment = ${cols}[2];

    $self->{$action}->{$num} = $comment;
  }
}

####################################################################
# @param1: 要素番号
# @param2: コメント
#
sub insert_divide {
  my $self = shift;
  my $num = shift;
  my $comment = shift;

  #読込＆解析
  $self->init();

  unless($self->{'DIVIDE'}->{$num}){
    my $datpath = "$self->{workdir}/$self->{filename}";
    open my $hF, '>>', $datpath || die "can't open ${datpath}";
    #書込み
    my $line = "${num}:DIVIDE:${comment}\n";
    print $hF $line;
    close $hF;
  }
}

####################################################################
# @param1: 要素番号
#
sub remove_divide {
  my $self = shift;
  my $num = shift;

  $self->init();

  if($self->{'DIVIDE'}->{$num}){
    my $datpath = "$self->{workdir}/$self->{filename}";
    open my $hF, '>', $datpath || die "can't open ${datpath}";
    foreach (keys %{$self->{'DIVIDE'}}) {
      if($_ ne $num) {
        my $cnum = $_;
        my $ccomment = $self->{'DIVIDE'}->{$cnum};
        my $line = "${cnum}:DIVIDE:${ccomment}\n";
        print $hF $line;
      }
    }
    close $hF;
  }
}

####################################################################
#
sub get_divides {
  my $self = shift;
  my $ret;
  for (sort { $a <=> $b } (keys %{$self->{'DIVIDE'}})) {
    push @$ret, $_;
  }
  return $ret;
}

1;
