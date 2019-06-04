#!/usr/bin/perl
# Use this script to split all files named a.b.c.sql a.b.c.plh or a.b.c.plb
# in the current directory into a directory tree a/b/c.sql or a/b/c.plh etc..

use File::Copy;
foreach(<*.*.*.sql>,<*.*.*.plh>,<*.*.*.plb>){
  chomp;
  m/(.+)\.(.+)\.(.+\..+)/;
  mkdir(qq|$1|,0777) if(!-d "$1");
  mkdir(qq|$1/$2|,0777) if(!-d "$1/$2");
  move($_,qq|$1/$2/$3|);
}
