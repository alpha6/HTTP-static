#!/usr/bin/perl -w

use strict;
use IO::Socket;
use Encode;
use Cwd;
use File::Spec;
use Carp;
use Getopt::Long;

use Data::Dumper;

our $VERSION = '0.0.1';

my $port = 8080;
my $cwd  = getcwd;

GetOptions( 'port=i' => \$port );

# Создаем сокет
socket( SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp') )
  or die("Не могу создать сокет!");
setsockopt( SOCK, SOL_SOCKET, SO_REUSEADDR, 1 );

# Связываем сокет с портом
my $paddr = sockaddr_in( $port, INADDR_ANY );
bind( SOCK, $paddr ) or die("Can't bind port!");

# Ждем подключений клиентов
print "Waiting for connections ($port)...\n";
listen( SOCK, SOMAXCONN );
while ( my $client_addr = accept( CLIENT, SOCK ) ) {

    # Получаем адрес клиента
    my ( $client_port, $client_ip ) = sockaddr_in($client_addr);
    my $client_ipnum = inet_ntoa($client_ip);
    my $client_host = gethostbyaddr( $client_ip, AF_INET );

    # Принимаем данные от клиента
    my $data;

    my $count = sysread( CLIENT, $data, 1024 );

    my $req_data = parse_header($data);

    #Server reply content
    my $reply;
    if ( $req_data->{'req_uri'} ) {
        my $dest = File::Spec->catfile( $cwd, $req_data->{'req_uri'} );
        unless ( -e $dest ) {
            $reply = get_404();
        }
        else {
            if ( -d $dest ) {
                $reply = get_dir_content($dest);
            }
            else {
                $reply = get_file_content($dest);
            }
        }
    }
    else {
        $reply = get_405();
    }

    # Отправляем данные клиенту
    print CLIENT $reply;

    # Закрываем соединение
    close(CLIENT);
}

sub parse_header {
    my $header_str = shift;

    #removing empty lines
    $header_str =~ s/^(?:\015?\012)+//;
    my @header = split /\015?\012/, $header_str;    #Because \r\n isn't portable

    my $header_data = {};

    #Now accepting only GET method
    if ( $header[0] =~ m!^GET (/.*?) HTTP! ) {
        $header_data->{'req_uri'} = $1;
    }

    return $header_data;
}

sub get_dir_content {
    my $dest = shift;

    my $files = [];
    my $reply = "Oooops! Something wrong!";
    $dest =~ s!\/+!/!g;

    my $base = substr( $dest, length($cwd) );

    eval {
        opendir( my $D, $dest ) or die $!;
        for my $file ( readdir $D ) {
            my $path = $base . '/' . $file;
            $path =~ s!/+!/!g;
            push @$files, { path => $path, fn => $file };
        }
        closedir $D;
        $reply = _get_file_list($files);
    };
    if ($@) {
        print STDERR "ERROR! [$@]";
        return get_500($@);
    }

    return $reply;
}

sub get_file_content {
    my $file = shift;

    my $reply;
    my $header = q~HTTP/1.0 200 OK
Content-Type: application/octet-stream;

~;

    my $buf;
    eval {
        open( my $fh, '<', $file ) or die $!;
        if ( my $size = -s $fh ) {
            my ( $pos, $read ) = 0;
            do {
                defined( $read = read $fh, ${$buf}, $size - $pos, $pos )
                  or croak "Couldn't read $file: $!";
                $pos += $read;
            } while ( $read && $pos < $size );
        }
        else {
            $buf = do { local $/; <$fh> };
        }
    };
    if ($@) {
        print STDERR "ERROR! [$@]";
        return get_500($@);
    }

    return sprintf( '%s%s', $header, $$buf );
}

sub _get_file_list {
    my $files_list = shift;

    my $header = q~HTTP/1.0 200 OK
Content-Type: text/html;

<html><head><style>.page-content { width: 400px; margin: 0 auto; border: 1px solid black; border-radius: 5px; padding: 5px 20px 30px } a {color: black } p { margin: 0; padding: 5px; } p:nth-child(even) {background: #D4F1D4}  </style></head><body><div class="page-content">~;

    my $footer = q~</div></body></html>~;

    my $content;
    for my $f (@$files_list) {
        $content .= "<p><a href=$f->{'path'}>$f->{'fn'}</a></p>";
    }

    return $header . $content . $footer;
}

sub get_404 {
    return q~HTTP/1.0 404 Not Found

File not found!
  ~;
}

sub get_405 {
    return q~HTTP/1.0 405 Method Not Allowed

Only GET method is allowed!
  ~;
}

sub get_500 {
    my $msg = shift;
    return qq~HTTP/1.0 500 Internal server error

Internal server error!
$msg
  ~;

}
