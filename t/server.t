use strict;
use utf8;

use Test::TempDir::Tiny;
use Test::More;
use Test::Deep;

use HTTP::Tiny;
use File::Spec;
use File::Temp qw/tempfile/;
use IPC::Open2;
use Cwd;

use Data::Dumper;

use File::Slurper;


my $exutable = File::Spec->catfile( getcwd(), 'server.pl' );

my $dir = tempdir();
chdir $dir;
mkdir 'dir1';
open my $fh, '>', 'index.txt';
print $fh 'index.txt content';
close $fh;

open my $fh, '>', 'dir1/file1.txt';
print $fh 'file1.txt content';
close $fh;


warn "[$exutable]";

my ( $chld_out, $chld_in );
my $pid = open2( $chld_out, $chld_in, $exutable, '--port', 8181 );
sleep 1; #Waiting for server start

subtest 'check server works' => sub {
    my @reply = _make_request( 'http://127.0.0.1:8181', 'GET' );
    cmp_deeply( \@reply, [ 200, ignore() ], "Got status 200 on index" );

		my @reply1 = _make_request( 'http://127.0.0.1:8181/index.txt', 'GET' );
		cmp_deeply( \@reply1, [ 200, 'index.txt content' ], "Got content on index.txt" );

		my @reply2 = _make_request( 'http://127.0.0.1:8181/dir1/file1.txt', 'GET' );
		cmp_deeply( \@reply2, [ 200, 'file1.txt content' ], "Got content from dir1/file1.txt" );
};

subtest 'test errors' => sub {
	for my $method (qw/POST PUT DELETE HEAD/) {
		my @reply = _make_request('http://127.0.0.1:8181', $method);
		cmp_deeply( \@reply, [ 405, ignore() ], "No $method allowed" );
	}

	{
		my @reply = _make_request('http://127.0.0.1:8181/no-file-link', 'GET');
		cmp_deeply( \@reply, [ 404, ignore() ], "File not found" );
	}

	{
		my @reply = _make_request('http://127.0.0.1:8181/no-dir-link/', 'GET');
		cmp_deeply( \@reply, [ 404, ignore() ], "Dir not found" );
	}

};


done_testing;

kill 'HUP', $pid;
waitpid ($pid, 0);


sub _make_request {
    my $uri    = shift;
    my $method = shift;

    my $http = HTTP::Tiny->new();
    my $response = $http->request( $method, $uri );


		# warn "$response->{status} $response->{reason}\n";
		# warn Dumper($response) unless ($response->{status} == 200);

    return ( $response->{status}, $response->{content} );

}
