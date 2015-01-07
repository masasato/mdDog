package mdDog;

use strict; no strict "subs";
use base APPBASE;
use Git::Wrapper;
use Data::Dumper;
use File::Copy;
use File::Basename;
use File::Path;
use Date::Manip;
use Text::Markdown::Discount qw(markdown);
use NKF;
use Cwd;
use Image::Magick;
use JSON;
use MYUTIL;
use mdDog::GitCtrl;
use mdDog::OutlineCtrl;

use constant THUMBNAIL_SIZE => 150;

sub new {
  my $pkg = shift;
  my $base = $pkg->SUPER::new(@_);

  my $hash = {
    repo_prefix => "user_",
    git         => undef,
    outline     => undef,
  };
  @{$base}{keys %{$hash}} = values %{$hash};

  return bless $base, $pkg;
}

###################################################
#
sub setupConfig {
  my $self = shift;

  if($self->qParam('fid')){
    my $workdir = "$self->{repodir}/" . $self->qParam('fid');
    $self->{git} = GitCtrl->new($workdir);
    $self->{outline} = OutlineCtrl->new($workdir);
  }

  $self->SUPER::setupConfig();
}

sub setOutline_buffer{
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);

  $self->{git}->attachLocal_tmp($uid);
  $self->{outline}->init();
  $self->{git}->detachLocal();

  my $divides = $self->{outline}->getDivides();
  $self->{t}->{divides} = $divides;
}

############################################################
#ログイン処理
#
sub login {
  my $self = shift;

  if($self->qParam('login')){
    my $account = $self->qParam('account');
    my $password = $self->qParam('password');

    my $sql = "select id from docx_users where account = '$account' and password = md5('$password') and is_used = true;";
    my @ary = $self->{dbh}->selectrow_array($sql);
    if(@ary){
      $self->{s}->param("login", $ary[0]);
    }
  }

  #ログアウト処理
  if($self->qParam('logout')){
    $self->{s}->clear("login");
    $self->{s}->close;
    $self->{s}->delete;
  }

  my $id = $self->{s}->param("login");
  if($id){
    my $sql = "select account,mail,nic_name,may_admin,may_approve,may_delete from docx_users where id = ${id} and is_used = true;";
    my $ha = $self->{dbh}->selectrow_hashref($sql);
    $self->{user} = {
      account     => $ha->{account},
      mail        => $ha->{mail},
      nic_name    => $ha->{nic_name},
      may_admin   => $ha->{may_admin},
      may_approve => $ha->{may_approve},
      may_delete  => $ha->{may_delete},
    };
    return 1;
  }
  return 0;
}


############################################################
#出力処理
#
sub printPage {
  my $self = shift;

  if($self->{s}->param("login")){
    $self->{t}->{login} = $self->{s}->param("login");
  }
  if($self->{user}){
    $self->{t}->{account} = $self->{user}->{account};
    $self->{t}->{is_admin} = $self->{user}->{may_admin};
    $self->{t}->{is_approve} = $self->{user}->{may_approve};
    $self->{t}->{is_delete} = $self->{user}->{may_delete};
  }

  $self->SUPER::printPage();
}

############################################################
#登録されたドキュメント一覧の取得してテンプレートにセット
#
sub listupDocuments {
  my $self = shift;
  my @infos;

  my $sql = "select
  di.*,
  du.nic_name as nic_name,
  du.account as account,
  du.mail as mail
from docx_infos di
join docx_users du on du.id = di.created_by
where di.deleted_at is null
order by di.is_used DESC, di.created_at desc;";
=pod
  id,
  file_name,
  is_used,
  to_char(created_at,'YYYY-MM-DD hh:mm:ss') as created_at,
  to_char(deleted_at,'YYYY-MM-DD hh:mm:ss') as deleted_at,
=cut

  my $ary = $self->{dbh}->selectall_arrayref($sql, +{Slice => {}})
     || $self->errorMessage("DB:Error",1);
  if(@$ary){
    foreach (@$ary) {
      my @logs = GitCtrl->new("$self->{repodir}/$_->{id}")->getSharedLogs();
      my $info = {
        id        => $_->{id},
        file_name => $_->{file_name},
        is_used   => $_->{is_used},
        created_at => MYUTIL::formatDate2($_->{created_at}),
        deleted_at => !$_->{deleted_at}?undef:MYUTIL::formatDate2($_->{deleted_at}),
        created_by => $_->{nic_name},
        file_size => MYUTIL::numUnit(-s $self->{repodir} . "/$_->{id}/$_->{file_name}"),
        last_updated_at => ${logs}[0][0]->{attr}->{date},
      };
      push @infos, $info;
    }
    $self->{t}->{infos} = \@infos;
  }
}

############################################################
# ドキュメント情報を取得してテンプレートにセット
sub setDocumentInfo {
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $user = $self->qParam('user');
  my $ver = $self->qParam('revision');
  return unless($fid);

  my $sql = "select
  di.*,
  du.nic_name as nic_name,
  du.account as account,
  du.mail as mail
from docx_infos di
join docx_users du on di.created_by = du.id and du.is_used = 't'
where di.id = $fid;";
  my $ary = $self->{dbh}->selectrow_hashref($sql);
  if($ary) {
    $self->{t}->{file_name} = $ary->{file_name};
    $self->{t}->{is_mdfile} = 1 if($ary->{file_name} =~ m/.*\.md/);
    $self->{t}->{created_at} = MYUTIL::formatDate2($ary->{created_at});
    $self->{t}->{created_by} = $ary->{nic_name};
    my @logs = $self->{git}->getSharedLogs();
    $self->{t}->{last_updated_at} = ${logs}[0][0]->{attr}->{date};
    $self->{t}->{file_size} = MYUTIL::numUnit(-s $self->{repodir} . "/${fid}/$ary->{file_name}");
  }

  $self->{t}->{fid} = $fid;
  $self->{t}->{user} = $user;
  $self->{t}->{revision} = $ver if($ver);
}


############################################################
#
sub isExistBuffer {
    my $self = shift;
    my $fid = $self->qParam('fid');
    my $uid = $self->{s}->param("login");

    if($self->{git}->isExistUserBranch($uid, {tmp=>1})){
        return $self->{git}->isUpdatedBuffer($uid);
    }
    return 0;
}


############################################################
#
sub gitLog {
  my $self = shift;
  my $all = shift;

  my $fid = $self->qParam("fid");
  my $uid = $self->{s}->param("login");
  my @userary;
  my $latest_rev = undef;
  my $gitctrl = $self->{git};

  #共有リポジトリ(master)
  $self->{t}->{sharedlist} = $gitctrl->getSharedLogs();
  $latest_rev = $self->{t}->{sharedlist}->[0]->{id} if($self->{t}->{sharedlist});

  if($all and $uid){ #ユーザーリポジトリ
    #自分のリポジトリ
    my $mylog = {
      uid     => $uid,
      name    => $self->{user}->{account},
      loglist => [],
    };
    if($gitctrl->isExistUserBranch($uid)){
      $mylog->{loglist} = $gitctrl->getUserLogs($uid);
      my $user_root = $gitctrl->getBranchRoot($uid);
      $mylog->{is_live} = $latest_rev =~ m/^${user_root}[0-9a-z]+/ ?1:0;
    }else{
      $mylog->{is_live} = 1;
    }
    push @userary, $mylog;
    if($self->{user}->{may_approve}){
      #承認者
      foreach($gitctrl->getOtherUsers($uid)){
        my $userlog = {
          uid       => $_,
          name      => $self->getAccount($_),
          loglist   => $gitctrl->getUserLogs($_),
        };

        my $userRoot = $gitctrl->getBranchRoot($_);
        if($latest_rev =~ m/${userRoot}[0-9a-z]+/ && (@{$userlog->{loglist}})) {
          $userlog->{is_live} = 1;
          push @userary, $userlog;
        }
      }
    }
  }
  $self->{t}->{userlist} = \@userary;
}

###################################################
# 承認するために指定したリヴィジョンまでの履歴を取得してテンプレートにセット
#
sub setApproveList {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  my $fid = $self->qParam("fid");
  my $revision = $self->qParam("revision");
  my $user = $self->qParam("user");
  return unless($uid && $fid && $revision && $user);
  my $branch = "$self->{repo_prefix}${user}";

  my @logs;
  my $flg = undef;
  my $branches = $self->{git}->getUserLogs($user);
  for (@$branches){
    my $obj = eval {($_)};
    my $rev = $obj->{id};
    if($flg
       || (!$flg && $obj->{id} eq ${revision}) ){
      push @logs, $obj;
      $flg = 1 unless($flg);
    }
  }
  $self->{t}->{loglist} = \@logs;
  $self->{t}->{approve_pre} = 1;
}

###################################################
# 指定のユーザーの指定のリヴィジョンを承認して共有化
#
sub docApprove {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  my $fid = $self->qParam("fid");
  my $revision = $self->qParam("revision");
  my $user = $self->qParam("user");
  return unless($uid && $fid && $revision && $user);

  $self->{git}->approve($user, $revision);
}


###################################################
# 新規でdocxファイルを登録する
# その際にアップロードしたユーザーブランチを作成
# 同名のファイルを許容する
sub uploadDOCX {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $hF = $self->{q}->upload('uploadfile');
  my $filename = basename($hF);
  my $fid = $self->setupNewFile($filename);

  my $tmppath = $self->{q}->tmpFileName($hF);
  my $filepath = $self->{repodir}. "/$fid/$filename";
  move ($tmppath, $filepath) || die "Upload Error!. $filepath";
  close($hF);

  $self->{git} = GitCtrl->new("$self->{repodir}/${fid}");
  $self->{git}->init($fid, $filename, $self->getAuthor($uid));

  $self->dbCommit();
}

###################################################
# MDファイルを作る
sub createFile {
  my $self = shift;
  my $uid = $self->{s}->param("login");
  
  my $docname = nkf("-w", $self->qParam('docname'));
  $docname =~ s/^\s*(.*)\s*$/\1/;
  $docname =~ s/\s/_/g;
  $docname =~ s/^(.*)\..*$/\1/;
  return unless($docname);

  my $filename = $docname . "\.md";
  my $fid = $self->setupNewFile($filename, $uid);
  my $workdir = "$self->{repodir}/${fid}";
  my $filepath = "${workdir}/${filename}";
  open my $hF, ">", $filepath || die "Create Error!. $filepath";
  close($hF);

  $self->{git} = GitCtrl->new($workdir);
  $self->{outline} = OutlineCtrl->new($workdir);
  $self->{git}->init($fid, [$filename, $self->{outline}->{filename}], $self->getAuthor($uid));

  $self->dbCommit();
}

###################################################
#
sub setupNewFile{
  my $self = shift;
  my $filename = shift;
  my $uid = shift;

 my $sql_insert = "insert into docx_infos(file_name,created_at,created_by) values('$filename',now(),$uid);";
  $self->{dbh}->do($sql_insert) || $self->errorMessage("DB:Error uploadFile", 1);
  my $sql_newfile = "select currval('docx_infos_id_seq');";
  my @ary_id = $self->{dbh}->selectrow_array($sql_newfile);
  my $fid = $ary_id[0];
  mkdir("./$self->{repodir}/$fid",0776)
    || die "Error:uploadFile can't make a directory($self->{repodir}/$fid)";
  return $fid;
}


###################################################
# ユーザーのブランチにコミットする
#
sub commitFile {
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $uid = $self->{s}->param("login");
  return 0 unless($fid && $uid);

  my $author = $self->getAuthor($uid);
  my $message = $self->qParam('detail');
  my $hF = $self->{q}->upload('uploadfile');
  my $filename = basename($hF);

  my $sql_check = "select id from docx_infos where file_name = '$filename' and is_used = true;";
  my @ary_check = $self->{dbh}->selectrow_array($sql_check);
  if(!@ary_check || $ary_check[0] != $fid){
    $self->{t}->{error} = "違うファイルがアップロードされました";
    close($hF);
    return 0;
  }

  $self->{git}->attachLocal($uid, 1);

  my $tmppath = $self->{q}->tmpFileName($hF);
  my $filepath = $self->{repodir}. "/$fid/$filename";
  move ($tmppath, $filepath) || die "Upload Error!. $filepath";
  close($hF);

  if(!$self->{git}->commit($filename, $author, $message)){
    $self->{t}->{error} = "ファイルに変更がないため更新されませんでした";
  }
  $self->{git}->detachLocal();
  return 1;
}

###################################################
# ユーザーのブランチにアップロードしたファイルをコミットする
#
sub uploadFile {
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $uid = $self->{s}->param("login");
  return 0 unless($fid && $uid);
  my $author = $self->getAuthor($uid);
  my $hF = $self->{q}->upload('uploadfile');
  return 0 unless($hF);
  my $filename = basename($hF);

  my $sql_check = "select id from docx_infos where file_name = '$filename' and is_used = true;";
  my @ary_check = $self->{dbh}->selectrow_array($sql_check);
  if(!@ary_check || $ary_check[0] != $fid){
    $self->{t}->{error} = "違うファイルがアップロードされました";
    close($hF);
    return 0;
  }

  $self->{git}->attachLocal_tmp($uid, 1);

  my $tmppath = $self->{q}->tmpFileName($hF);
  my $filepath = $self->{repodir}. "/$fid/$filename";
  move ($tmppath, $filepath) || die "Upload Error!. $filepath";
  close($hF);

  if(!$self->{git}->commit($filename, $author, "rewrite by an uploaded file")){
    $self->{t}->{error} = "ファイルに変更がないため更新されませんでした";
  }
  $self->{git}->detachLocal();
  return 1;
}

###################################################
#
sub gitDiff{
  my $self = shift;
  my $ver = $self->qParam('revision');
  my $dist = $self->qParam('dist');

  $self->{t}->{difflist} = $self->{git}->getDiff($ver, $dist);
}

############################################################
#
sub changeFileInfo {
  my $self = shift;
  my $ope = shift;

  my $fid = $self->qParam('fid');
  return unless($fid);
  my $sql;

  if($ope =~ m/^use$/){
    $sql = "update docx_infos set is_used = true where id = $fid;";
  }elsif($ope =~ m/^unuse$/){
    $sql = "update docx_infos set is_used = false where id = $fid;";
  }elsif($ope =~ m/^delete$/){
    $sql = "update docx_infos set deleted_at = now() where id = $fid;";
    File::Path::rmtree(["./$self->{repodir}/$fid"]) || die("can't remove a directory: $fid");
  }
  $self->{dbh}->do($sql) || errorMessage("Error:changeFileInfo = $sql");

  $self->dbCommit();
}

############################################################
#
sub downloadFile {
  my $self = shift;
  my $fid = shift;
  my $rev = shift;

  my $sql = "select file_name from docx_infos where id = $fid;";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless($ary[0]);
  my $filename = $ary[0];
  my $filepath = "./$self->{repodir}/$fid/$filename";

  if($rev){
    $self->{git}->checkoutVersion($rev);
  }

  print "Content-type:application/octet-stream\n";
  print "Content-Disposition:attachment;filename=$filename\n\n";

  open (DF, $filepath) || die "can't open a file($filename)";
  binmode DF;
  binmode STDOUT;
  while (my $DFdata = <DF>) {
    print STDOUT $DFdata;
  }
  close DF;

  $self->{git}->detachLocal() if($rev);
}

############################################################
#
sub getAccount {
  my $self = shift;
  my $uid = shift;

  my $sql = "select account from docx_users where id = $uid;";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return $ary[0];
}

############################################################
#
sub getAuthor {
  my $self = shift;
  my $uid = shift;

  my $sql = "select account || ' <' || mail || '>' from docx_users where id = $uid;";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return $ary[0];
}

############################################################
# MDドキュメントをアウトライン用整形してテンプレートにセットする
# またドキュメントの情報もテンプレートにセットする
#
sub setOutline{
  my $self = shift;

  my $fid = $self->qParam('fid');
  return unless($fid);
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);

  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";
  my $md;
  my $user = undef;
  my $revision = undef;

  my $gitctrl = $self->{git};

  #MDファイルの更新履歴の整形
  $self->{t}->{loglist} = $gitctrl->getSharedLogs("DESC");

  #ドキュメントの読み込み
  $gitctrl->attachLocal($user);
  $gitctrl->checkoutVersion($revision);
  open my $hF, '<', $filepath || die "failed to read ${filepath}";
  my $pos = 0;
  while (my $length = sysread $hF, $md, 1024, $pos) {
    $pos += $length;
  }
  close $hF;
  $gitctrl->detachLocal();

  my @contents;

  $self->{outline}->init();
  my $divides = $self->{outline}->getDivides();
  my ($rowdata, @partsAry) = $self->split4MD($md);
  my ($i, $j) = 0;
  my ($docs, $dat);
  foreach (@partsAry) {
    if(@$divides[$i] == $j){
      push @$docs, $dat;
      $dat = undef;
      $i++;
    }

    my $line = markdown($_);
    $line =~ s#"md_imageView\.cgi\?(.*)"#"md_imageView.cgi?master=1&\1" #g;
    $dat .= $line;

    if( $line =~ m/<h1.*>/){
      $line =~ s#<h1.*>(.*)</h1>#\1#;
      push @contents, {level => 1, line => $line};
    }elsif( $line =~ m/<h2.*>/ ){
      $line =~ s#<h2.*>(.*)</h2>#\1#;
      push @contents, {level => 2, line => $line};
    }elsif( $line =~ m/<h3.*>/ ){
      $line =~ s#<h3.*>(.*)</h3>#\1#;
      push @contents, {level => 3, line => $line};
    }elsif( $line =~ m/<h4.*>/ ){
      $line =~ s#<h4.*>(.*)</h4>#\1#;
      push @contents, {level => 4, line => $line};
    }

    $j++;
  }
  if($dat ne ""){
    push @$docs, $dat;
  }

  $self->{t}->{revision} = $revision;
  $self->{t}->{contents} = \@contents;
  $self->{t}->{docs} = $docs;
}

############################################################
# MDドキュメントをテンプレートにセットする
# またドキュメントの情報もテンプレートにセットする
#
sub setMD{
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);

  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";
  my $document;
  my $user = $self->qParam('user');         # 'user'指定無しだとmasterへ
  my $revision = $self->qParam('revision'); # 'revision'指定無しだと最新リヴィジョンへ

  my $gitctrl = $self->{git};

  my $user_root = $gitctrl->getBranchLatest($user);
  $revision = $user_root unless($revision);
  $self->{t}->{git_is_latest} = $revision =~ m/^${user_root}$/ ?1:0;
  $self->{t}->{is_buffer} = $user?1:0;
  my $oneLog = $gitctrl->oneLog($revision);
  $self->{t}->{git_comment} = $oneLog->{message};
  $self->{t}->{git_commit_date} = MYUTIL::formatDate1($oneLog->{attr}->{date});

  $gitctrl->attachLocal($user);
  $gitctrl->checkoutVersion($revision);

  open my $hF, '<', $filepath || die "failed to read ${filepath}";
  my $pos = 0;
  while (my $length = sysread $hF, $document, 1024, $pos) {
    $pos += $length;
  }
  close $hF;

  $gitctrl->detachLocal();

  $self->{t}->{revision} = $revision;
  $self->{t}->{document} = markdown($document);
}

############################################################
# MDドキュメントの編集バッファをテンプレートにセットする
sub setMD_buffer{
  my $self = shift;
  my $preview = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid');
  my $document = $self->getUserDocument($uid, $fid);

  unless($preview){
    $self->{t}->{document} = $document;
    $self->{t}->{style} = "source";
  }else {
    my ($rowdata, @partsAry) = $self->split4MD($document);
    my $md;
    my $cnt = 0;

    foreach (@partsAry) {
      my $conv = markdown($_);
      $conv =~ s/^<([a-z1-9]+)>/<\1 id=\"md${cnt}\" class=\"Md\">/;
      $conv =~ s#^<([a-z1-9]+) />#<\1 id=\"md${cnt}\" class=\"Md\" />#;
      $md .= $conv;
      $cnt++;
    }

    $self->{t}->{rowdata} = $rowdata;
    $self->{t}->{markdown} = $md;
    $self->{t}->{style} = "preview";
  }
}

############################################################
# MDドキュメントの編集バッファを更新する
sub updateMD_buffer {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  my $fid = $self->qParam('fid');
  return 0 unless($uid && $fid);
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return 0 unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";
  my $document = $self->qParam('document');
  $document =~ s#<div>\n##g;
  $document =~ s#</div>\n##g;
  $document =~ s/\r\n/\n/g;

  $self->{git}->attachLocal_tmp($uid, 1);

  #ファイル書き込み
  open my $hF, '>', $filepath || die "failed to read ${filepath}";
  syswrite $hF, $document;
  close $hF;

  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->commit($filename, $author, "temp saved");
  $self->{git}->detachLocal();
  return 1;
}

############################################################
# MDドキュメントの編集バッファをフィックスする
sub fixMD_buffer {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  my $fid = $self->qParam('fid');
  my $comment = $self->qParam('comment');
  return 0 unless($uid && $fid && $comment);

  if($self->qParam('document')){
    return 0 unless($self->updateMD_buffer());
  }
  $self->{git}->fixTmp($uid, $self->getAuthor($uid), $comment);
  return 1;
}

############################################################
# MDドキュメントで管理している画像一覧を取得
#
sub setMD_image{
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid');

  my $imgdir = "$self->{repodir}/${fid}/image";

  unless(-d $imgdir){
    mkdir $imgdir, 0774 || die "can't make image directory.";
  }

  $self->{git}->attachLocal_tmp($uid);
  my @images = glob "$imgdir/*";
  $self->{git}->detachLocal();

  my @imgpaths;
  foreach (@images) {
    my $path = $_;
    $path =~ s#$self->{repodir}/${fid}/image/(.*)$#\1#g;
    push @imgpaths, $path;
  }

  $self->{t}->{images} = \@imgpaths;
  $self->{t}->{uid} = $self->{s}->param("login");
}

############################################################
# 画像をアップロードしてユーザーの編集バッファにコミット
#
sub upload_image {
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $uid = $self->{s}->param("login");
  return 0 unless($fid && $uid);

  my $hF = $self->{q}->upload('imagefile');
  my $filename = basename($hF);

  $self->{git}->attachLocal_tmp($uid, 1);

  my $tmppath = $self->{q}->tmpFileName($hF);
  my $imgdir = "$self->{repodir}/${fid}/image";
  my $filepath = "${imgdir}/${filename}";
  unless(-d $imgdir){
    mkdir $imgdir, 0774 || die "can't make image directory.";
  }
  move ($tmppath, $filepath) || die "Upload Error!. $filepath";
  close($hF);

  my $thumbnail = $self->add_thumbnail($fid, $filename);

  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->addImage($filepath, $author);
  $self->{git}->addImage($thumbnail, $author);

  $self->{git}->detachLocal();
  return 1;
}

############################################################
# 画像のサムネイルを作成
#
sub add_thumbnail {
  my $self = shift;
  my $fid = shift;
  my $filename = shift;

  my $imgpath = "$self->{repodir}/${fid}/image/${filename}";
  my $thumbdir = "$self->{repodir}/${fid}/thumb";
  unless(-d $thumbdir){
    mkdir $thumbdir, 0774 || die "can't make thumbnail directory.";
  }

  my $mImg = Image::Magick->new();
  $mImg->Read($imgpath);
  my ($w, $h) = $mImg->get('width', 'height');
  my ($rw, $rh);
  if ($w >= $h) {
    $rw = THUMBNAIL_SIZE;
    $rh = THUMBNAIL_SIZE / $w * $h;
  } else {
    $rh = THUMBNAIL_SIZE;
    $rw = THUMBNAIL_SIZE / $h * $w;
  }
  $mImg->Resize(width=>$rw, height=> $rh);
  $mImg->Write("${thumbdir}/${filename}");
  return "${thumbdir}/${filename}";
}

############################################################
#
sub delete_image {
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $uid = $self->{s}->param("login");
  return 0 unless($uid && $fid);

  my @selected = ($self->qParam('select_image'));

  $self->{git}->attachLocal_tmp($uid);
  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->deleteImage([@selected], $author);
  $self->{git}->detachLocal();
  return 1;
}

############################################################
#
sub printImage {
  my $self = shift;

  my $tmp = $self->qParam('tmp');
  my $fid = $self->qParam('fid');
  my $uid = $self->{s}->param("login");
#  my $uid = $self->qParam("uid");
  my $image = $self->qParam('image');
  my $thumbnail = $self->qParam('thumbnail');

  return unless($image && $fid);

  my $imgpath;
  unless($thumbnail){
    $imgpath = "$self->{repodir}/${fid}/image/${image}";
  } else {
    $imgpath = "$self->{repodir}/${fid}/thumb/${image}";
  }

  if($uid && $tmp){
    $self->{git}->attachLocal_tmp($uid);
  }else{
    $self->{git}->attachLocal($uid);
  }

  if( -f $imgpath ){
    my $type = $imgpath;
    $type =~ s/.*\.(.*)$/\1/;
    $type =~ tr/A-Z/a-z/;

    print "Content-type: image/${type}\n\n";

    my $mImg = Image::Magick->new();
    $mImg->Read($imgpath);
    binmode STDOUT;
    $mImg->Write($type . ":-");
  }
  $self->{git}->detachLocal();
}


############################################################
# JSONを返す
sub api_getData {
  my $self = shift;
  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid');
  my $eid = $self->qParam('eid');

  if($self->qParam('action') eq 'image_list'){
      $self->{git}->attachLocal_tmp($uid);
      my $data;
      my $imgdir = "$self->{repodir}/${fid}/image";
      if( -d $imgdir){
          my @images = glob "$imgdir/*";
          $self->{git}->detachLocal();

          foreach (@images) {
              my $path = $_;
              $path =~ s#$self->{repodir}/${fid}/image/(.*)$#\1#g;
              push @$data, {filename => $path};
          }
      }
      my $json = JSON->new();
      return $json->encode($data);
  } else {
      my $document = $self->getUserDocument($uid, $fid);
      my ($rowdata, @partsAry) = $self->split4MD($document);
      my $cnt = 0;
      my $data;

      foreach (@partsAry) {
          if ($eid) {
              if ($eid == $cnt) {
                  $data = [{eid => ${cnt}, data => $_}];
                  last;
              }
          } else {
              push @$data, { eid => ${cnt}, data => $_ };
          }
          $cnt++;
      }

      my $json = JSON->new();
      return $json->encode($data);
  }
}

############################################################
#
sub api_postData {
  my $self = shift;
  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid') + 0;
  my $eid = $self->qParam('eid') + 0;
  my $data = $self->qParam('data');
  $data .= "\n" if( $data !~ m/(.*)\n$/);
  $data .= "\n" if( $data !~ m/(.*)\n\n$/);
  my $document = $self->getUserDocument($uid, $fid);
  my ($rowdata, @partsAry) = $self->split4MD($document);

  $self->{git}->attachLocal_tmp($uid, 1);

  #ファイル書き込み
  # TODO: ファイル名取得ルーチンが重複！
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";

  open my $hF, '>', $filepath || return undef;
  my $cnt = 0;
  my @newAry;
  my $line;
  foreach(@partsAry) {
    if($eid == $cnt){
      $line = $data . "\n";
    }else{
      $line = $_ . "\n";
    }
    syswrite $hF, $line, length($line);
    $cnt++;
  }
  close $hF;

  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->commit($filename, $author, "temp saved");
  $self->{git}->detachLocal();

  my $json = JSON->new();
  my $md;# = markdown($data);
  my ($row, @parts) = $self->split4MD($data, $eid);
  $cnt = $eid;
  foreach(@parts){
    my $conv .= markdown($_)    if($_ !~ m/^\n*$/);
    $conv =~ s/^<([a-z1-9]+)>/<\1 id=\"md${cnt}\" class=\"Md\">/;
    $conv =~ s#^<([a-z1-9]+) />#<\1 id=\"md${cnt}\" class=\"Md\" />#;
    $conv =~ s/^(.*)\n$/\1/;
    $md .= $conv;
    $cnt++;
  }
  return $json->encode({eid => ${eid}, md => ${md}, row => ${row}});
}

############################################################
#
sub api_deleteData {
  my $self = shift;
  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid') + 0;
  my $eid = $self->qParam('eid');

  my $document = $self->getUserDocument($uid, $fid);
  my ($rowdata, @partsAry) = $self->split4MD($document);

  $self->{git}->attachLocal_tmp($uid, 1);

  #ファイル書き込み
  # TODO: ファイル名取得ルーチンが重複！
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";

  open my $hF, '>', $filepath || return undef;
  my $cnt = 0;
  foreach(@partsAry) {
    if($eid != $cnt){
      my $line = $_ . "\n";
      syswrite $hF, $line, length($line);
    }
    $cnt++;
  }
  close $hF;

  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->commit($filename, $author, "temp saved");
  $self->{git}->detachLocal();

  my $json = JSON->new();
  return $json->encode({eid => ${eid}});
}

############################################################
#
sub api_outline_addDivide {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid') + 0;

  my $num = $self->qParam('num');
  my $author = $self->getAuthor($self->{s}->param('login'));
  my $comment = "INSERT DIVIDE";
  $self->{git}->attachLocal_tmp($uid, 1);
  $self->{outline}->insertDivide($num, $comment);
  $self->{git}->commit($self->{outline}->{filename}, $author, $comment);
  $self->{git}->detachLocal();
  my $json = JSON->new();
  return $json->encode({action => 'divide',num => ${num}});
}

############################################################
#
sub api_outline_removeDivide {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid') + 0;

  my $num = $self->qParam('num');
  my $author = $self->getAuthor($self->{s}->param('login'));
  my $comment = "REMOVE DIVIDE";
  $self->{git}->attachLocal_tmp($uid, 1);
  $self->{outline}->removeDivide($num);
  $self->{git}->commit($self->{outline}->{filename}, $author, $comment);
  $self->{git}->detachLocal();
  my $json = JSON->new();
  return $json->encode({action => 'undivide',num => ${num}});
}

############################################################
#
sub getUserDocument {
  my $self = shift;
  my $uid  = shift;
  my $fid  = shift;

  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";

  $self->{git}->attachLocal_tmp($uid);

  my $document;
  open my $hF, '<', $filepath || die "failed to read ${filepath}";
  my $pos = 0;
  while (my $length = sysread $hF, $document, 1024, $pos) {
    $pos += $length;
  }
  close $hF;
  $self->{git}->detachLocal();

  return $document;
}

############################################################
#
sub split4MD {
  my $self = shift;
  my $document = shift;
  my $index = shift;

  my @partsAry;
  my $parts = "";
  my $rowdata = "";
  my $block = 0;
  my $blockquote = 0;
  my $quote = 0;
  my $cnt = $index?$index:0;
  foreach (split(/\n/, $document)) {
    if ( $blockquote && $_ !~ m/^> .*/ ) {
      $blockquote = 0;
      push @partsAry, $parts;
      $rowdata .= "${parts}</div>";
      $parts = "";
      $cnt++;
    }

    if ( !$block && !$blockquote ) {
      if ( $_ =~ m/^.+$/ ) {
          unless( $_ =~ m/^> .+/ ){
              $block = 1;
          }else{
              $blockquote = 1;
          }
          $rowdata .= "<div id=\"elm${cnt}\" class=\"Elm\">";
      }
    } else {
      if ( $_ =~ m/^\s*$/ ) {
        $blockquote = 0;
        $block = 0;
        push @partsAry, $parts;
        $rowdata .= "${parts}</div>";
        $parts = "";
        $cnt++;
      } elsif ( !$blockquote && $_ =~ m/^> .*/) {
        $blockquote = 1;
        $block = 0;
        push @partsAry, $parts;
        $rowdata .= "${parts}</div>";
        $parts = "";
        $cnt++;
        $rowdata .= "<div id=\"elm${cnt}\" class=\"Elm\">";
      } elsif ( $block && $_ =~ m/^(====|----|#+).*/ ) {
        push @partsAry, $parts;
        $rowdata .= "${parts}</div>";
        $parts = "";
        $cnt++;
        $rowdata .= "<div id=\"elm${cnt}\" class=\"Elm\">";
      }
    }

    if ($block || $blockquote || $quote) {
      $parts .= $_ . "\n";
    }

    if ( $block && $_ =~ m/^(====|----|#+).*/ ) {
      $block = 0;
      push @partsAry, $parts;
      $rowdata .= "${parts}</div>";
      $parts = "";
      $cnt++;
    }
  }
  if ($block || $blockquote || $quote) {
    push @partsAry, $parts;
    $rowdata .= "${parts}</div>";
  }

  return ($rowdata, @partsAry);
}

1;
