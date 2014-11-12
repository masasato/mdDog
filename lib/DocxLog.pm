package DocxLog;

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
use MYUTIL;
use DocxLog::GitCtrl;


sub new {
  my $pkg = shift;
  my $base = $pkg->SUPER::new(@_);

  my $hash = {
    repo_prefix => "user_",
    git         => undef,
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
  }

  $self->SUPER::setupConfig();
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
  }
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
  id,file_name,is_used,to_char(created_at,'YYYY-MM-DD hh:mm:ss'),to_char(deleted_at,'YYYY-MM-DD hh:mm:ss')
from docx_infos
where deleted_at is null
order by is_used DESC, created_at desc;";

  my $ary = $self->{dbh}->selectall_arrayref($sql) || $self->errorMessage("DB:Error",1);
  if(@$ary){
    foreach (@$ary)
    {
      my $info = {
        id        => $_->[0],
        file_name => $_->[1],
        is_used   => $_->[2],
        created_at => $_->[3],
        deleted_at => $_->[4],
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

  my $sql = "select id, file_name, is_used, created_at, deleted_at from docx_infos where id = $fid;";
  my @ary = $self->{dbh}->selectrow_array($sql);
  if(@ary) {
    $self->{t}->{file_name} = $ary[1];
    $self->{t}->{is_mdfile} = 1 if($ary[1] =~ m/.*\.md/);
  }

  $self->{t}->{fid} = $fid;
  $self->{t}->{user} = $user;
  $self->{t}->{revision} = $ver if($ver);
}


############################################################
#
sub gitLog {
  my $self = shift;

  my $fid = $self->qParam("fid");
  my $uid = $self->{s}->param("login");
  my @userary;
  my $latest_rev = undef;
  my $gitctrl = $self->{git};

  #共有リポジトリ(master)
  $self->{t}->{sharedlist} = $gitctrl->getSharedLogs();
  $latest_rev = $self->{t}->{sharedlist}->[0]->{id} if($self->{t}->{sharedlist});

  if($uid){ #ユーザーリポジトリ
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
sub uploadFile {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $hF = $self->{q}->upload('docxfile');
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
  my $fid = $self->setupNewFile($filename);
  my $filepath = $self->{repodir}. "/$fid/$filename";
  open my $hF, ">", $filepath || die "Create Error!. $filepath";
  close($hF);

  $self->{git} = GitCtrl->new("$self->{repodir}/${fid}");
  $self->{git}->init($fid, $filename, $self->getAuthor($uid));

  $self->dbCommit();
}

###################################################
#
sub setupNewFile{
  my $self = shift;
  my $filename = shift;

 my $sql_insert = "insert into docx_infos(file_name,created_at) values('$filename',now());";
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

  my $author = $self->getAuthor($uid);
  my $message = $self->qParam('detail');
  my $hF = $self->{q}->upload('docxfile');
  my $filename = basename($hF);

  my $sql_check = "select id from docx_infos where file_name = '$filename' and is_used = true;";
  my @ary_check = $self->{dbh}->selectrow_array($sql_check);
  if(!@ary_check || $ary_check[0] != $fid){
    $self->{t}->{error} = "違うファイルがアップロードされました";
    close($hF);
    return;
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

  my $git = Git::Wrapper->new("$self->{repodir}/$fid");
  if($rev){
    $git->checkout($rev);
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

  $git->checkout("master");
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
# MDドキュメントをテンプレートにセットする
sub setMD{
  my $self = shift;

  my $fid = $self->qParam('fid');
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";
  my $document;
  my $uid = $self->{s}->param("login");

  $self->{git}->attachLocal($uid);

  open my $hF, '<', $filepath || die "failed to read ${filepath}";
  my $pos = 0;
  while (my $length = sysread $hF, $document, 1024, $pos) {
    $pos += $length;
  }
  close $hF;

  $self->{git}->detachLocal();

  $self->{t}->{document} = markdown($document);
}

############################################################
# MDドキュメントの編集バッファをテンプレートにセットする
sub setMD_buffer{
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);

  my $fid = $self->qParam('fid');
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
  $self->{t}->{row_document} = $document;
  $self->{git}->detachLocal();
  $self->{t}->{style} = "source";
}

############################################################
# MDドキュメントの編集バッファを更新する
sub updateMD_buffer {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  return unless($uid);
  my $fid = $self->qParam('fid');
  my $sql = "select file_name from docx_infos where id = ${fid};";
  my @ary = $self->{dbh}->selectrow_array($sql);
  return unless(@ary);
  my $filename = $ary[0];
  my $filepath = "$self->{repodir}/${fid}/${filename}";
  my $document = $self->qParam('row_document');

  $self->{git}->attachLocal_tmp($uid, 1);

  #ファイル書き込み
  open my $hF, '>', $filepath || die "failed to read ${filepath}";
  syswrite $hF, $document;
  close $hF;

  my $author = $self->getAuthor($self->{s}->param('login'));
  $self->{git}->commit($filename, $author, "temp saved");
  $self->{git}->detachLocal();
}

############################################################
# MDドキュメントの編集バッファをフィックスする
sub fixMD_buffer {
  my $self = shift;

  my $uid = $self->{s}->param("login");
  my $fid = $self->qParam('fid');
  my $comment = $self->qParam('comment');
  return 0 unless($uid && $fid && $comment);

  $self->updateMD_buffer();
  $self->{git}->fixTmp($uid, $self->getAuthor($uid), $comment);
  return 1;
}
1;
