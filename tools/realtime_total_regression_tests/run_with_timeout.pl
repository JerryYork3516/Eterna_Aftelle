#!/usr/bin/perl

use strict;
use warnings;

@ARGV >= 2 or die "usage: run_with_timeout.pl seconds command [args...]\n";
my $seconds = shift @ARGV;
$seconds =~ /^\d+$/ && $seconds > 0
    or die "timeout must be a positive integer\n";

sub process_tree {
    my ($root) = @_;
    my %children;
    if (open my $ps, '-|', '/bin/ps', '-axo', 'pid=,ppid=') {
        while (my $line = <$ps>) {
            next unless $line =~ /^\s*(\d+)\s+(\d+)\s*$/;
            push @{ $children{$2} }, $1;
        }
        close $ps;
    }

    my @queue = ($root);
    my @tree;
    my %seen;
    while (@queue) {
        my $pid = shift @queue;
        next if $seen{$pid}++;
        push @tree, $pid;
        push @queue, @{ $children{$pid} // [] };
    }
    return reverse @tree;
}

sub terminate_tree {
    my ($root) = @_;
    my @targets = process_tree($root);
    kill 'TERM', @targets;
    select undef, undef, undef, 0.25;
    my @alive = grep { kill 0, $_ } @targets;
    kill 'KILL', @alive if @alive;
}

my $pid = fork();
die "fork failed: $!\n" unless defined $pid;
if ($pid == 0) {
    exec @ARGV;
    die "exec failed: $!\n";
}

my $timed_out = 0;
local $SIG{ALRM} = sub {
    $timed_out = 1;
    terminate_tree($pid);
};

alarm $seconds;
waitpid($pid, 0);
my $status = $?;
alarm 0;

exit 124 if $timed_out;
exit 128 + ($status & 127) if $status & 127;
exit $status >> 8;
