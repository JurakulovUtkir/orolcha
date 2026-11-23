#!/usr/bin/perl
# MediaBridge.dylib ni Apple imzolagan perl ichida ishga tushiradi.
use strict;
use warnings;
use DynaLoader;

my $lib = $ARGV[0] or die "foydalanish: media-bridge.pl /yo'l/MediaBridge.dylib\n";
my $handle = DynaLoader::dl_load_file($lib, 0) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($handle, "orolcha_run") or die DynaLoader::dl_error();
DynaLoader::dl_install_xsub("main::orolcha_run", $sym);
orolcha_run();
