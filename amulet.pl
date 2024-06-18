#!/usr/bin/env perl
#############################################################################
# IRSSI plugin to hunt for amulets in sequential chatter.
# ----------------------------------------------------------------------------
# An amulet is a kind of poem that depends on language, code, and luck.
# To qualify, a poem must satisfy these criteria:
#
#  Its complete Unicode text is 64 bytes or less.
#  The hexadecimal SHA-256 hash of the text includes four or more 8s in a row.
#
# There are no other rules! An amulet can be written in any language and any
# style. It can be composed, generated, or “discovered” in any way.
#
#      https://www.robinsloan.com/special/amulet/definition/
#############################################################################

use autodie;
use feature 'say';
use strict;
use warnings;
use Cwd 'getcwd';
use Digest::SHA qw(sha256_hex);
use Encode      qw(encode_utf8);
use File::Path  qw(make_path);
use POSIX       qw(strftime);
use Term::ANSIColor;

our $VERSION = '1.00';
our %IRSSI   = (
  authors     => 'shmup',
  contact     => 'shmup@smell.flowers',
  name        => 'amulet finder',
  url         => 'https://github.com/shmup/amulet.pl',
  description => 'hunt for amulets in sequential chatter',
  license     => 'Artistic-2.0',
);

my $amulet_regex = qr/(?:8{4,})/;

sub main {
  if (-t STDIN && @ARGV == 0) {
    test();
  } else {
    local $/;    # read all input at once by unsetting record separator
    my $input = @ARGV ? join(' ', @ARGV) : <>;
    process_input($input);
  }
}

sub test {
  process_input("DON'T WORRY.");
  process_input("If you can't write poems,\nwrite me");
  process_input("   #zakyz");
}

sub process_input {
  my ($input) = @_;
  my ($found, $rarity, $text) = extract_amulet($input);
  if ($found) {
    say color('bright_green'), "found $rarity", color('reset');
  }
}

sub extract_amulet {
  my ($text) = @_;
  my $hash = sha256_hex($text);
  if (length(encode_utf8($text)) <= 64) {
    if ($hash =~ /($amulet_regex)/) {
      return (1, $1, $text);
    }
  }
  return (0);
}

my $is_irssi = defined $Irssi::VERSION ? 1 : 0;

if (!$is_irssi) {
  main();
  exit;
}

Irssi::settings_add_str('amulet', 'amulet_log_path', "$ENV{HOME}/amulets/");
Irssi::settings_add_int('amulet', 'amulet_max_history_size', 20);
Irssi::settings_add_str('amulet', 'amulet_channels', '');

my %channel_history;
my @chans            = split(/ /, Irssi::settings_get_str('amulet_channels'));
my $log_dir_path     = Irssi::settings_get_str('amulet_log_path');
my $max_history_size = Irssi::settings_get_int('amulet_max_history_size');

Irssi::command_bind('amulet_add_channel',    'cmd_add_channel');
Irssi::command_bind('amulet_remove_channel', 'cmd_remove_channel');
Irssi::signal_add_last('message public',     'check_for_amulets');
Irssi::signal_add_last('message own_public', 'check_for_own_amulets');

sub check_for_own_amulets {
  my ($server, $msg, $target) = @_;
  my $nick = $server->{nick};

  check_for_amulets($server, $msg, $nick, '', $target);
}

sub check_for_amulets {
  my ($server, $msg, $nick, $address, $target) = @_;

  return unless grep { $_ eq $target } @chans;

  push @{ $channel_history{$target} }, { text => $msg, nick => $nick };
  shift @{ $channel_history{$target} }
    while @{ $channel_history{$target} } > $max_history_size;

  my $combined_text     = $msg;
  my @contributing_msgs = ({ text => $msg, nick => $nick });

  evaluate_and_record_amulet($combined_text, @contributing_msgs);

  # Prepend previous messages and evaluate up until 64 bytes
  for (my $i = $#{ $channel_history{$target} } - 1; $i >= 0; $i--) {
    my $history_msg       = $channel_history{$target}[$i];
    my $new_combined_text = "$history_msg->{text}\n$combined_text";

    if (length(encode_utf8($new_combined_text)) <= 64) {
      unshift @contributing_msgs, $history_msg;
      $combined_text = $new_combined_text;

      evaluate_and_record_amulet($combined_text, @contributing_msgs);
    } else {
      last;    # stop when over 64 bytes
    }
  }
}

sub evaluate_and_record_amulet {
  my ($combined_text, @contributing_msgs) = @_;
  my ($found, $rarity, $text) = extract_amulet($combined_text);
  if ($found) {
    write_amulet_to_file($rarity, $text, @contributing_msgs);
  }
}

sub write_amulet_to_file {
  unless (-d $log_dir_path) {
    make_path($log_dir_path);
  }

  my ($rarity, $amulet, @original_msgs) = @_;
  my $timestamp     = strftime("%Y%m%d%H%M%S", localtime);
  my $log_file_name = "${rarity}_amulet_${timestamp}.txt";
  my $log_file_path = "${log_dir_path}${log_file_name}";

  open(my $fh, '>:encoding(UTF-8)', $log_file_path)
    or die "Cannot open file: $log_file_path";
  print {$fh} "$rarity\n\n$amulet\n\n";

  foreach my $msg_entry (@original_msgs) {
    print {$fh} "<$msg_entry->{nick}> $msg_entry->{text}\n";
  }

  close $fh;
}

sub cmd_add_channel {
  my ($data, $server, $witem) = @_;
  if ($data !~ /^[#&][^\x07\x2C\s]{0,200}$/) {
    say "nope. needs to look like a #channel";
    return;
  }
  push @chans, $data unless grep { $_ eq $data } @chans;
  Irssi::settings_set_str('amulet_channels', join(' ', @chans));
  say "Added $data to amulet channels.";
}

sub cmd_remove_channel {
  my ($data, $server, $witem) = @_;
  @chans = grep { $_ ne $data } @chans;
  Irssi::settings_set_str('amulet_channels', join(' ', @chans));
  delete $channel_history{$data};
  say "Removed $data from amulet channels.";
}

sub announce_load {
  my $chans_list = join(', ', @chans);
  say "Amulet script $VERSION loaded. Listening to channels: $chans_list";
}

announce_load();
