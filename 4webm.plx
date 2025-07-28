#!/usr/bin/perl
#
# RDEPEND: ffmpeg, SvtVp9EncApp
# 4webm: A simple webm converter script using ffmpeg, SVT-VP9 compatible
########################################################################

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage qw(pod2usage);
use POSIX qw(strftime ceil floor);
use Term::ANSIColor;
use File::Basename;
use Env;
use IPC::Run qw(run);
use File::Copy;
use Cwd qw(abs_path);
#use Win32::Console::ANSI;

use LWP::UserAgent;
use HTTP::Request;
use JSON;

use Time::HiRes qw(time);

# Defaults

my $audio;
my $audio_state = "false";
my $audio_opts = "-an";
my $arate_adjust = my $arate = my $margin = 0;
my $board = ["g"];
my $board_audio;
my $libcv = "libvpx-vp9";
my $libca = "libopus";
my $quality = "good";
my $tune = 0;
my $extra_args = "";
my $LOWLIMIT = 10;
my $OVERHEAD = 7;
my $audio_overhead = 3;

# System variables

my $library_path;
my $ffmpeg;
my $ffprobe;
my $ffmpeg_path;
my $os = $^O;
my $svtvp9;
my $svt_path;
my $dir = (-l __FILE__)? dirname(readlink(__FILE__)) : dirname(__FILE__);
my $nul = ($os eq "MSWin32")? "NUL" : "/dev/null";

if ($ENV{PAR_0}) {
    my $env_dir = "$ENV{PAR_PROGNAME}";
    
    if ($os eq "MSWin32") {
	$env_dir =~ s/\\[\w\-\,\;\.\:\#\+\~\´\`\=\{\}\(\)\[\]\&\%\$\§\!]+\.exe$//;
    }
    else {
	$env_dir =~ s/\/\w+$//;
    }
    
    $dir = "$env_dir/$dir";
}

# Global variables

my $ffprobe_output;
my $duration;
my $file_size_limit;
my $max_dur;
my $c_bitrate;
my $nominal_rate;
my $stime;
my $etime;
my @start;
my @end;
my $bitrate;
my $user_keyspace;
my $input;
my $svt_args = "";
our $infile;
our $aspect = "";
my $rc_mode;
my $speed;
my $keep = 0;
my $crop_reference;
my $framerate;
my @orig_framerate;
my $h_resolution;
my $v_resolution;
my $h_limit_resolution = my $v_limit_resolution = 2048;
our $outfile;
my $force;
my $break_limits;
my $break_duration;
my $audio_recog;
our $q_value = 55; #unused
our $encoder_option = "none";
my $audident;
my $vidident;
my $randomise;
my $debug;
my $pod = my $man = 0;

GetOptions(
    'audio|a:f' => \&setAudio,
    'autocrop:f' => \&setAutoCrop,
    'board|b=s@' => \$board,
    'debug|d' => \$debug,
    'end|e=s' => \$etime,
    'extra|x=s' => \$extra_args,
    'extra-svt=s' => \$svt_args,
    'force|f' => \$force,
    'ftplaylist' => \&getPlaylists,
    'input|i=s@' => \$input,
    'keep' => \$keep,
    'keyframe=i' => \$user_keyspace,
    'legacy' => \&setEncoder,
    'library|l=s@' => \$library_path,
    'margin|m=f' => \$margin,
    'output|o=s' => \$outfile,
    'quality|q=s' => \$quality,
    'q-value=i' => \$q_value,
    'random' => \$randomise,
    'rate-control=i' => \$rc_mode,
    'recognise|recognize|r' => \$audio_recog,
    'remove-limits' => \$break_limits,
    'remove-duration' => \$break_duration,
    'start|s=s' => \$stime,
    'svt-vp9|t' => \&setEncoder,
    'speed|v=i' => \$speed,
    'tune=i' => \$tune,
    'help|h|?' => \$pod,
    'man' => \$man
    ) or pod2usage(-sections => "SYNOPSIS", -input => "$dir/usage.pod");

die colored(["red"], "Insufficient arguments!")," Type 4webm -h for a short usage screen.\nExiting...\n" unless (@$input[0] || $pod || $man);

pod2usage(-sections => "SYNOPSIS", -input => "$dir/usage.pod") if $pod;
pod2usage(-perldocopt => "-o man",-verbose => 2, -input => "$dir/usage.pod") if $man;

die colored(["red"],"Input file/directory not found or empty!"),"\n" unless (-f @$input[0] || -s @$input[0] || -d @$input[0]);
die colored(["red"],"File not found!")," Check file handle.\n" if (-f @$input[0] && @$input[0] !~ m/\.\w{2,4}$/);

if (@$library_path[0]) {
    if (scalar @$library_path == 1) {
	if (-e "@$library_path[0]/ffmpeg") {
	    $ffmpeg_path = @$library_path[0];
	}
	elsif (-e "@$library_path[0]/SvtVp9EncApp") {
	    $svt_path = @$library_path[0];
	}
	else {
	    die colored(["red"],"Unrecognised library")," Check if directory contains ffmpeg/SvtVp9EncApp.\n";
	}
    }
    elsif (scalar @$library_path == 2) {
	if (-e "@$library_path[0]/ffmpeg" && -e "@$library_path[1]/SvtVp9EncApp") {
	    $ffmpeg_path = @$library_path[0];
	    $svt_path = @$library_path[1];
	}
	elsif (-e "@$library_path[0]/SvtVp9EncApp" && -e "@$library_path[1]/ffmpeg") {
	    $svt_path = @$library_path[0];
	    $ffmpeg_path = @$library_path[1];
	}
	else {
	    die colored(["red"],"Unrecognised library")," Check if directories contain ffmpeg/SvtVp9EncApp.\n";
	}
    }
}

$ffmpeg = "ffmpeg";
$ffprobe = "ffprobe";

if ($ffmpeg_path) {
    print "Specified ffmpeg \$DIR = $ffmpeg_path\n";
    $ffmpeg = "$ffmpeg_path/ffmpeg";
    $ffprobe = "$ffmpeg_path/ffprobe";
}
else {
    for my $path (split(":", $ENV{PATH})) {
	if (-f "$path/$ffmpeg" && -x _) {
	    print "Found ffmpeg in $path/$ffmpeg\n" if ($debug);
	    $ffmpeg = "ffmpeg";
	    $ffprobe = "ffprobe";
	    $ffmpeg_path = "$path/$ffmpeg";
	    last;
	}
    }
    unless ($ffmpeg_path) {
	print "ffmpeg not found in \$PATH nor specified with --library\nUsing bundled executables.\n" if ($debug);
	$ffmpeg = "$dir/ffmpeg/bin/ffmpeg";
	$ffprobe = "$dir/ffmpeg/bin/ffprobe";
    }
}

$svtvp9 = "SvtVp9EncApp";

if ($svt_path) {
    print "Specified SvtVp9EncApp \$DIR = $svt_path\n";
    $svtvp9 = "$ffmpeg_path/SvtVp9EncApp";
}
else {
    for my $path (split(":", $ENV{PATH})) {
	if (-f "$path/$svtvp9" && -x _) {
	    print "Found SvtVp9EncApp in $path/$svtvp9\n" if ($debug);
	    $svtvp9 = "SvtVp9EncApp";
	    $svt_path = "$path/$svtvp9";
	    last;
	}
    }
    unless ($svt_path) {
	print "SvtVp9EncApp not found in \$PATH nor specified with --library\nUsing bundled executables.\n" if ($debug);
	$svtvp9 = "$dir/SVT-VP9/SvtVp9EncApp";
    }
}

sub getOutfile {
    my $infile = $_[0];
    my $no_date = $_[1];
    my $date = strftime "%d%b%Y_%H-%M-%S", localtime;
    ($outfile) = $infile =~ m/(.*)\.\w{2,4}/s;
    $outfile = "$outfile\_$date" unless ($no_date);
    return $outfile;
}

sub proceed {
    my $affirm = "y";
    unless ($force) {
	print "Proceed? [",colored(["green"],"y"),"/",colored(["red"],"n"),"]: ";
	$affirm = <STDIN>;
	chomp $affirm;
    }
    my $encoder_option = $_[0];

    if (($affirm eq "y" || $affirm eq "Y") && $encoder_option eq "fix") {
	print "Re-encoding audio\n";
	encodeAudio("$outfile" . ".webm");
    }
    elsif (($affirm eq "y" || $affirm eq "Y") && $encoder_option eq "music") {
	print "Encoding\n";
	encodeMusic(@$input[1]);
    }
    elsif(($affirm eq "y" || $affirm eq "Y") && $libcv eq "svt-vp9") {
	print "Encoding\n";
	encodeSvtVp9();
    }
    elsif (($affirm eq "y" || $affirm eq "Y") && ($libcv eq "libvpx-vp9" || $libcv eq "libvpx")) {
	print "Encoding\n";
	encode();
    }
    else {
	die colored(["yellow"],"\nExiting..."),"\n";
    }
}

sub getBitrate {
    (my $target, my $duration) = @_;
    my $eq_const_bitrate = $target * 2**20 * 0.008 / $duration;
    return $eq_const_bitrate;
}

my $eq_bitrate = sub {
    return setBitrateGeneric($ffprobe_output,
			     $_[0],
			     $duration,
			     $OVERHEAD);
};

sub encode {
    my $keyspace = "-g " . $framerate * 8;
    my $keyintmin = "";
    
    if ($user_keyspace) {
	$keyspace = "-g " . $user_keyspace;
    }
    elsif ($break_limits) {
	my $framecount = getFramecount() + 1;
	$keyintmin = "-keyint_min " . $framecount;
	$keyspace = "-g " . $framecount;
    }
	
    print colored(["magenta"],"\nPass 1/2:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -c:v $libcv -b:v "$bitrate"K $keyspace $keyintmin -pass 1 -quality good -speed 4 $extra_args -an -f rawvideo -y $nul);
    print colored(["magenta"],"\nPass 2/2:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -c:v $libcv -b:v "$bitrate"K $keyspace $keyintmin -pass 2 -quality $quality -speed $speed $extra_args $audio_opts -row-mt 1 -map_metadata -1 -y "$outfile".webm);
    unlink "ffmpeg2pass-0.log";
    checkFileSize("$outfile.webm");
}

sub encodeAudio {
    my $audio_file = $_[0];
    my $arg2 = ($_[1]) ? $_[1] : "";
    print colored(["magenta"],"Pass 1/1:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -vn $audio_opts "$infile"_audio.opus);
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$audio_file" -i "$infile"_audio.opus -c:v copy $audio_opts -map 0:v:0 $arg2 $aspect -map 1:a:0 -shortest -map_metadata -1 -y "$outfile"_remux.webm);
    unlink "$infile\_audio.opus";
}

sub demuxAudio {
    my $audio_type = shift;
    print colored(["magenta"],"Demuxing audio stream 1/1:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" -vn -c:a copy -map_metadata -1 "$outfile"."$audio_type");
}

sub encodeMusic {
    my $cover = shift;
    print colored(["magenta"],"Transcoding audio 1/1:"),"\n";
    if ($cover) {
	qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" -i "$cover" -map 1:v:0 -pix_fmt yuv420p -c:v libvpx-vp9 -r 1 -map 0:a:0 -c:a libopus -b:a "$bitrate"K -map_metadata -1 -y "$outfile".webm);
    }
    else {
	qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" -pix_fmt yuv420p -c:v libvpx-vp9 -r 1 -c:a libopus -b:a "$bitrate"K -map_metadata -1 -y "$outfile".webm);
    }
}

sub encodeSvtVp9 {
    my $alt = $_[0];
    $bitrate = floor($bitrate * 1000);
    
    unless ($rc_mode) {
	$rc_mode = ($bitrate > 100000)? "1" : "2";
    }
    
    my $bsfv = "-bsf:v vp9_superframe";
    my $max_rate = $bitrate * 1.25;
    my $buf_size = $bitrate * 0.25;
    my $keyspace = ($framerate == 29.97 || $framerate == 59.94)? 239 : $framerate * 8 - 1;

    if ($user_keyspace && $user_keyspace < 256) {
	$keyspace = $user_keyspace - 1;
    }
    elsif ($break_limits) {
	$keyspace = "-1";
	$rc_mode = "0 -q $q_value";
    }
    else {
	if ($keyspace > 255 && $framerate % 25 == 0) {
	    $keyspace = 199;
	}
	elsif ($keyspace > 255 && $framerate % 30 == 0) {
	    $keyspace = 239;
	}
	elsif ($keyspace > 255) {
	    $keyspace = "";
	}
    }

    if ($alt) {
	print colored(["magenta"],"\nDemuxing, Stage 1/2:"),"\n";
	run("$ffmpeg -hide_banner -loglevel error -stats -i \"$infile\" -pix_fmt yuv420p $stime $etime $extra_args -y raw.yuv") unless (-e "raw.yuv" && $keep);
	print colored(["magenta"],"\nEncoding, Stage 2/2:"),"\n";
	run("$svtvp9 -i raw.yuv -w $h_resolution -h $v_resolution -intra-period $keyspace -fps-num $orig_framerate[0] -fps-denom $orig_framerate[1] -rc $rc_mode -tbr $bitrate -min-qp 0 -max-qp 60 -tune $tune -enc-mode $speed \"$svt_args\" -b \"$outfile.ivf\"");
	unlink "raw.yuv" unless ($keep);
    }
    else {
	my $frames = getFramecount();
	run("$ffmpeg -hide_banner -loglevel error -stats -i \"$infile\" -pix_fmt yuv420p $stime $etime $extra_args - | $svtvp9 -i stdin -w $h_resolution -h $v_resolution -intra-period $keyspace -fps-num $orig_framerate[0] -fps-denom $orig_framerate[1] -rc $rc_mode -tbr $bitrate -min-qp 0 -max-qp 60 -tune $tune -enc-mode $speed \"$svt_args\" -n $frames -b \"$outfile.ivf\"");
    }

    if ($audio) {
	print "\n",colored(["magenta"],"Muxing audio"),"\n";
	encodeAudio("$outfile.ivf",$bsfv);
	unlink "$outfile.ivf";
	checkFileSize("$outfile\_remux.webm");
    }
    else {
	qx($ffmpeg -hide_banner -loglevel error -stats -i "$outfile".ivf -c:v copy $bsfv -y "$outfile".webm);
	unlink "$outfile.ivf";
	checkFileSize("$outfile.webm");
    }
}

sub removeDuration {
    my $out = $_[0];
    my $webm_fh;
    my $webm_bin = "";
    my $bytes_read;
    my $pos = 0;
    my @hexdata;

    copy($out,"$out.old") or die "Backup copy failed!\n";
    open $webm_fh,"+<",$out;
    binmode $webm_fh,":raw";

    do {
	$bytes_read = read $webm_fh,$webm_bin,128,length($webm_bin);
	die "Read error, received incorrect data.\n" unless ($bytes_read);
	
        @hexdata = unpack('H2'x(length($webm_bin)),$webm_bin);

	while ($pos < length($webm_bin)) {
	    goto FOUND if ($hexdata[$pos] eq 44 && $hexdata[$pos+1] eq 89);
	    $pos = $pos + 1;
	}
    } while($bytes_read == 128);
    
    FOUND:print "Found 0x44 0x89 \@ $pos ($hexdata[$pos],$hexdata[$pos+1],$hexdata[$pos+2])\n";

    seek $webm_fh,$pos+2,0;
    print $webm_fh 0b00000000;
    close $webm_fh;
}

sub postAudio {
    my $form_type = $_[0];
    my $file = $_[1];
    my $returns = $_[2];
    my $token;
    if (-e "$dir/api_token.txt") {
	my $token_fh;
	
	open($token_fh,'<',"$dir/api_token.txt") or die "Can't open file $!\n";
	$token = <$token_fh>;
	chomp $token;
	close($token_fh);
    }
    else {
	$token = 'test';
	print "Using test api token. While free and perpetual, it is rate limited.\n";
	print "You may provide your own api token by writing it into a file called api_token.txt\n";
    }
    
    my $ua = LWP::UserAgent->new(protocols_allowed => ['https']);
    
    my $response = $ua->post('https://api.audd.io/', "Content-Type"=>'form-data',"Content"=>[$form_type=>["$file"],return=>"$returns",api_token=>"$token"],);
    die $response->status_line unless $response->is_success;
    
    my $response_content = $response->content;
    my $decoded = decode_json($response_content);
    die "Song not found or rate limited.\n" unless $decoded->{'result'};
    
    print "Song Name: ",$decoded->{'result'}{'title'},"\n";
    print "by: ",$decoded->{'result'}{'artist'},"\n";
    print "Album: ",$decoded->{'result'}{'album'},"\n";
}

sub getContent {
    my $url = shift;
    my $ua = LWP::UserAgent->new(protocols_allowed=>['https']);
    my $response = $ua->get("$url");
    die $response->status_line unless $response->is_success;

    my $response_content = $response->content;
    my $decoded = decode_json($response_content);
    return $decoded;
}

sub getFTm3u8 {
    my $json = getContent('https://api.fishtank.live/v1/live-streams');

    my $streams = $json->{'liveStreams'};

    open(my $fh,'>','playlist.m3u') or die "Could not create playlist.m3u\n";
    print $fh "#EXTM3U\n";
    
    foreach my $i (0..(scalar(@$streams)-1)){
        my $cam = $streams->[$i];
	print $i,"\n" if $debug;
	
	my $id = $cam->{'id'};
	my $name = $cam->{'name'};
	my $suffix = $cam->{'jwt'};
	my $cdn = $json->{'loadBalancer'}{$id};
	unless ($suffix){
	    $suffix = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIzNmU5YzA0Zi02OWU0LTQxZTMtYWY3OC1hZDJkZTNlOGM5ZWYiLCJsaXZlU3RyZWFtSWQiOiJjYW1lcmEtOS00IiwiaWF0IjoxNzUwMDkyNTM2LCJleHAiOjE3NTAxNzg5MzZ9.xQ3mNpY_VV6bd7bzXMGlPiyJB6YOXAXws-ONEWKNtV8';
	}
	my $link = "https://$cdn/hls/live+$id/index.m3u8?jwt=$suffix";
	print $name,"\n",$link,"\n" if $debug;
	
	print $fh "#EXTINF:0, - $name\n";
	print $fh $link,"\n";
    }

    close $fh;
}

sub getPPVm3u8 {
    my $json = getContent('https://ppvs.su/fishtank.json');

    my $streams = $json->{'streams'};

    open(my $fh,'>','playlist_ppv.m3u') or die "Could not create playlist.m3u\n";
    print $fh "#EXTM3U\n";

    foreach my $i (0..(scalar(@$streams)-1)){
	my $cam = $streams->[$i];
	print $i,"\n" if $debug;

	my $name = $cam->{'name'};
	my $link = $cam->{'playlist'};
	print $name,"\n",$link,"\n" if $debug;

	print $fh "#EXTINF:0, - $name\n";
	print $fh $link,"\n";
    }

    close $fh;
}

sub getPlaylists {
    getFTm3u8;
    print "Saving FT playlist as: playlist.m3u\n";
    #getPPVm3u8;
    #print "Saving PPV playlist as: playlist_ppv.m3u\n";
    exit;
}

sub checkFileSize {
    my $outfile_size = -s $_[0];
    $outfile_size = $outfile_size / 2**20;
    
    if ($outfile_size > $file_size_limit) {
	my $delta = $outfile_size - $file_size_limit;
	($bitrate,$c_bitrate,$nominal_rate) = $delta->$eq_bitrate;
	print "\nThe output file size is: ",colored(["red"],"$outfile_size")," MiB, which is larger than the max. permissible filesize of $file_size_limit MiB\n";
	
	if ($audio) {
	    $arate_adjust = floor($arate_adjust - $nominal_rate);
	    
	    if ($arate_adjust > 32 && $libcv ne "svt-vp9") {
		$audio_opts = "-c:a $libca -b:a " . $arate_adjust . "K";
		print "Re-encode audio at $arate_adjust kbps to reduce the file size?";
		proceed("fix");
	    }
	    else {
		$margin = ceil($margin + $nominal_rate);
		print colored(["yellow"],"Fix attempt not possible.")," resulting audio bitrate would drop below threshold of 32 kbps. Rerun with \"--margin $margin\".\n";
	    }
	}
	else {
	    $margin = ceil($margin + $nominal_rate);
	    print "Rerunning with \"--margin $margin\" may bring the file size back within limits.\n";
	}
    }
    elsif ($outfile_size == 0) {
	die colored(["red"],"\nEncoding error:")," No output file was generated\n";
    }
    else {
	my $delta = $file_size_limit - $outfile_size;
	($bitrate,$c_bitrate,$nominal_rate) = $delta->$eq_bitrate;
	$margin = ceil($margin - $nominal_rate);
	print "\nThe output file size is: ",colored(["green"],"$outfile_size")," MiB\n";
	
	if ($nominal_rate > $LOWLIMIT && $outfile_size != 0) {    
	    print "It may be possible to increase quality while staying within limits by setting \"--margin $margin\".\n";
	    if ($libcv eq "svt-vp9") {
		print "This is advisable for SVT-VP9 encoded media, if the output file size is significantly below limits.\n";
	    }
	}
    }
}

sub setAutoCrop {
    $crop_reference = ($_[1] != 0)? $_[1] : 1;
}

sub getAutoCrop {
    my $crop_detect = qx(ffmpeg -i "$infile" -vf cropdetect -t $crop_reference -f null - 2>&1);
    ($crop_detect) = $crop_detect =~ m/(crop=\d+:\d+:\d+:\d+)(?!.*crop=\d+:\d+:\d+:\d+)/s;

    if ($extra_args) {
	$extra_args = $extra_args . " -vf " . $crop_detect;
    }
    else {
	$extra_args = "-vf " . $crop_detect;
    }
}

sub setAudio {
    $audio = 1;
    $arate_adjust = ($_[1] != 0)? $_[1] : 96;
}

sub setEncoder {
    if ($_[0] eq "legacy") {
	$libcv = "libvpx";
	$libca = "libvorbis";
    }
    elsif ($_[0] eq "svt-vp9") {
	$OVERHEAD = 9;
	$libcv = "svt-vp9";
    }
}

@$board = split(/,/,join(",",@$board));

if (@$board[0] eq "wsg") {
    $file_size_limit = 6;
    $max_dur = 400;
    $board_audio = @$board[1] // 1;
}
elsif (@$board[0] eq "b" || @$board[0] eq "bant") {
    $file_size_limit = 2;
    $max_dur = 120;
    $board_audio = @$board[1] // 0;
}
elsif (@$board[0] eq "gif" || @$board[0] eq "wsr") {
    $file_size_limit = 4;
    $max_dur = 120;
    $board_audio = @$board[1] // 1;
}
elsif (@$board[0] =~ m/custom/i) {
    $file_size_limit = @$board[1];
    $max_dur = @$board[2];
    $board_audio = @$board[3] // 0;
    if (@$board[4]) {
	my @res = split(/x|:/,@$board[4]);
	$h_limit_resolution = $res[0];
	$v_limit_resolution = $res[1];
    }
    die colored(["red"],"Custom board parameters incomplete.")," Required parameters: Max. file size in MiB, max. duration in s\n" unless ($file_size_limit && $max_dur);
    print <<EOF;

#######################################
        CUSTOM BOARD PARAMETERS
FILE SIZE LIMIT:	$file_size_limit MiB
DURATION LIMIT:		$max_dur s
AUDIO (0=off):         	$board_audio
MAX. RESOLUTION:	$h_limit_resolution x $v_limit_resolution
#######################################

EOF
}
else {
    $file_size_limit = 4;
    $max_dur = 120;
    $board_audio = @$board[1] // 0;
}

sub getJsonProbe {
    my $probe_file = shift;
    my $probe_output = qx($ffprobe -v quiet -print_format json -show_format -show_streams -i "$probe_file" 2>&1);
    $probe_output = decode_json($probe_output);
    
    if ($probe_output->{'streams'}[0]{'codec_type'} eq "audio") {
	$audident = 0;
	$vidident = 1;
    }
    else {
	$audident = 1;
	$vidident = 0;
    }
    
    return $probe_output;
}

sub getFramecount {
    my $framecount = qx(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$infile" 2>&1);
    return $framecount;
}

sub checkAudio {
    my $ffprobe_output = shift;
    if ($audio && $board_audio) {
	$audio_state = "true";
	$audio_opts = "-c:a $libca -b:a " . $arate_adjust . "K";
	$arate = $ffprobe_output->{'streams'}[$audident]{'bit_rate'};
	$arate = $ffprobe_output->{'format'}{'bit_rate'} unless $arate;
	$arate = $arate/1000;
    }
    elsif ($audio) {
	die colored(["red"],"\nBoard limit:")," The selected board does not support audio. Change board, disable audio or force encoding by setting -b/--board @$board,1\n";
    }   
}

sub getDuration {
    my $ffprobe_output = shift;
    my $duration;
    my $ffprobe_duration = $ffprobe_output->{'streams'}[$vidident]{'duration'};
    $ffprobe_duration = $ffprobe_output->{'format'}{'duration'} unless $ffprobe_duration;
    
    if ($stime && $etime) {
	@start = split(/:/,$stime);
	@end = split(/:/,$etime);
	@start = reverse(@start);
	@end = reverse(@end);
	push(@start,0,0);
	push(@end,0,0);
	$duration = ($end[0] - $start[0]) + 60 * ($end[1] - $start[1]) + 3600 * ($end[2] - $start[2]);
	$stime = "-ss $stime";
	$etime = "-to $etime";
    }
    elsif (defined $stime && not defined $etime) {
	@start = split(/:/,$stime);
	@start = reverse(@start);
	push(@start,0,0);
	my $end = $ffprobe_duration;
	$duration = $end - ($start[0]  + 60 * $start[1] + 3600 * $start[2]);
	$stime = "-ss $stime";
	$etime = "";
    }
    elsif (defined $etime && not defined $stime) {
	@end = split(/:/,$etime);
	@end = reverse(@end);
	push(@end,0,0);
	$duration = $end[0] + 60 * $end[1] + 3600 * $end[2];
	$stime = "";
	$etime = "-to $etime";
    }
    else {
	$duration = $ffprobe_duration;
	$stime = "";
	$etime = "";
    }
    
    if ($duration > $ffprobe_duration) {
	die "The specified end-point is past the total duration of the input file. Please check the -e/--end argument.\n";
    }
    elsif ($duration < 0) {
	die "The specified start-point is beyond the end-point of the input file. Please check the -st/--start argument.\n";
    }
    elsif ($duration > $max_dur) {
	die "The (specified) duration of the input file exceeds board limitations ($max_dur s). Please cut the video or specify a different board.\n";
    }
    return $duration;
}

sub setBitrateGeneric {
    (my $ffprobe_output, my $target, my $duration, my $overhead) = @_;
    my $c_bitrate = $ffprobe_output->{'format'}{'bit_rate'};
    $c_bitrate = $c_bitrate/1000;
    my $nominal_rate = getBitrate($target,$duration);
    my $nominal_rate_adj = floor($nominal_rate - $arate_adjust);
    
    my $bitrate = ($nominal_rate < ($c_bitrate + $overhead + 1))? $nominal_rate_adj - $margin - $overhead : $c_bitrate - $margin;
    return ($bitrate,$c_bitrate,$nominal_rate);
}

sub setBitrateAudio {
    (my $ffprobe_output, my $target, my $duration, my $audio_overhead) = @_;
    my $c_bitrate = $ffprobe_output->{'format'}{'bit_rate'};
    $c_bitrate = $c_bitrate/1000;
    my $nominal_rate = getBitrate($target,$duration);
    my $video_adjust = 8 * 100/$duration;
    my $nominal_rate_adj = floor($nominal_rate - $video_adjust);

    my $bitrate = ($nominal_rate < ($c_bitrate + $audio_overhead + 1))? $nominal_rate_adj - $margin - $audio_overhead : $c_bitrate - $margin;
    return ($bitrate,$c_bitrate,$nominal_rate);
}

sub setFramerate {
    my $ffprobe_output = shift;
    my $r_framerate = $ffprobe_output->{'streams'}[$vidident]{'r_frame_rate'};
    @orig_framerate = split("/",$r_framerate);
    
    if ($extra_args =~ m/fps/) {
	($framerate) = $extra_args =~ m/fps=(\d+(\.\d+)?)/;
	$orig_framerate[0] = $framerate * 100;
	$orig_framerate[1] = 100;
    }
    else {
	$framerate = $orig_framerate[0]/$orig_framerate[1];
    }
}

sub checkResolution {
    my $ffprobe_output = shift;
    my @aspect_fraction;
    my $aspect_ratio;
    $h_resolution = $ffprobe_output->{'streams'}[$vidident]{'width'};
    $v_resolution = $ffprobe_output->{'streams'}[$vidident]{'height'};
    my $sar = $ffprobe_output->{'streams'}[$vidident]{'sample_aspect_ratio'};
    my $dar = $ffprobe_output->{'streams'}[$vidident]{'display_aspect_ratio'};
    
    unless ($sar && $dar) {
	$aspect_ratio = $h_resolution/$v_resolution;
    }
    else {
	@aspect_fraction = split(":",$sar);

	unless ($h_resolution/$v_resolution == $aspect_fraction[0]/$aspect_fraction[1]) {
	    @aspect_fraction = split(":",$dar);
	}
	$aspect_ratio = $aspect_fraction[0]/$aspect_fraction[1];
    }

    if ($extra_args =~ m/scale=/sg) {
	my @scale_resolution = $extra_args =~ m/scale=(-?\d+):(-?\d+)/;
	($aspect) = $extra_args =~ m/(-aspect \d+:\d+)/;
	
	if ($scale_resolution[0] =~ m/^-/) {
	    $v_resolution = $scale_resolution[1];
	    $h_resolution = $v_resolution * $aspect_ratio;
	}
	elsif ($scale_resolution[1] =~ m/^-/) {
	    $h_resolution = $scale_resolution[0];
	    $v_resolution = $h_resolution / $aspect_ratio;
	}
	else {
	    $h_resolution = $scale_resolution[0];
	    $v_resolution = $scale_resolution[1];
	}
    }
    elsif ($extra_args =~ m/crop=/sg) {
	my @crop_resolution = $extra_args =~ m/crop=(-?\d+):(-?\d+)(:\d+)?(:\d+)?/;
	
	if ($crop_resolution[0] =~ m/^-/) {
	    $v_resolution = $crop_resolution[1];
	    $h_resolution = $v_resolution * $aspect_ratio;
	}
	elsif ($crop_resolution[1] =~ m/^-/) {
	    $h_resolution = $crop_resolution[0];
	    $v_resolution = $h_resolution / $aspect_ratio;
	}
	else {
	    $h_resolution = $crop_resolution[0];
	    $v_resolution = $crop_resolution[1];
	}
    }

    if ($h_resolution > $h_limit_resolution || $v_resolution > $v_limit_resolution) {
	die "The video resolution exceeds the maximum of ",colored(["yellow"],"2048x2048"),". Please scale or crop the input via -ex/--extra.\n";
    }

    if ($libcv eq "svt-vp9" && ($h_resolution % 8 != 0 || $v_resolution % 8 != 0)) {
	$libcv = "libvpx-vp9";
    }

    my $rotation = $ffprobe_output->{'streams'}[$vidident]{'side_data_list'}[0]{'rotation'};

    if ($rotation) {
	print "Rotation detected: ",$rotation," degrees.\n";
	print "It may be necessary to add -vf transpose=2 to --extra\n";
    }
}

sub setOptimisations {
    unless (defined $speed) {
	if ($v_resolution >= 720) {
	    $speed = 2;
	}
	else {
	    $speed = 1;
	}
    }    
}

sub randomName {
    #imitate unix-style epoch
    my @nums = ('0'..'9');
    my $random_name = '17';
    (my $suffix) = $infile =~ m/\.\w{1,4}/;
    
    do {
	foreach (1..14) {
	    $random_name = $random_name.$nums[rand(@nums)];
	}
    } while(-e "$random_name.$suffix");
    
    return $random_name;
}
    
sub printMediaInfo {
print color("magenta");
print <<EOF;
==================================================================================================
INPUT FILE:			$infile
OUTPUT FILE: 		        $outfile\.webm
SELECTED BOARD:			/@$board[0]/
AUDIO: 	 	 		$audio_state
EOF
if ($audio && $board_audio) {
    print "AUDIO CODEC:		        $libca\n";
    print "AUDIO BITRATE:	                $arate_adjust kbps\n";
}
print <<EOF;
VIDEO DURATION:			$duration s
VIDEO CODEC:			$libcv
SELECTED RESOLUTION:		$h_resolution x $v_resolution
VIDEO FRAMERATE:		$orig_framerate[0]/$orig_framerate[1] approx. $framerate fps
CURRENT TOTAL BITRATE:		$c_bitrate kbps
MAX. PERMISSIBLE BITRATE: 	$nominal_rate kbps
SELECTED VIDEO BITRATE:		$bitrate kbps
EOF
if ($extra_args) {
    print "FFMPEG ARGUMENTS:		$extra_args\n";
}
elsif ($break_limits || $user_keyspace) {
    print "FRAME COUNT:                    ",getFramecount(),"\n";
}
print <<EOF;
===================================================================================================
EOF
print color("reset");
}

sub convertFile {
    if ($randomise) {
	$outfile = randomName();
    }
    else {
	$outfile = getOutfile($infile,0) unless ($outfile);
    }
    
    $ffprobe_output = getJsonProbe($infile);
    checkAudio($ffprobe_output);
    $duration = getDuration($ffprobe_output);
    ($bitrate,$c_bitrate,$nominal_rate) = $file_size_limit->$eq_bitrate;
    getAutoCrop if ($crop_reference);
    setFramerate($ffprobe_output);
    checkResolution($ffprobe_output);
    setOptimisations();
    printMediaInfo();
    proceed($encoder_option);
}

sub convertMusic {
    my $cover = shift;
    
    if ($randomise) {
	$outfile = randomName();
    }
    else {
	$outfile = getOutfile($infile,0) unless ($outfile);
    }
    
    $ffprobe_output = getJsonProbe($infile);
    my $ffprobe_output_cover = getJsonProbe($cover) if $cover;
    checkAudio($ffprobe_output);
    $duration = getDuration($ffprobe_output);
    ($bitrate,$c_bitrate,$nominal_rate) = setBitrateAudio($ffprobe_output, $file_size_limit, $duration, $audio_overhead);
    $orig_framerate[0] = $orig_framerate[1] = $framerate = 1;
    
    if ($cover) {
	checkResolution($ffprobe_output_cover);
    }
    else {
	checkResolution($ffprobe_output);
    }
    
    $arate_adjust = $bitrate;
    printMediaInfo();
    proceed("music");
}

sub recogniseAudio {
    my $audio_path;
    my $audio_type;
    $outfile = randomName() unless ($outfile);
    
    my $decode_probe = getJsonProbe($infile);
    my $codec_name = $decode_probe->{'streams'}[$audident]{'codec_name'};
    
    if ($codec_name eq "aac") {
	$audio_type = "m4a";
    }
    elsif ($codec_name eq "mp3") {
	$audio_type = "mp3";
    }
    elsif ($codec_name eq "opus") {
	$audio_type = "opus";
    }
    elsif ($codec_name eq "vorbis") {
	$audio_type = "ogg";
    }
    else {
	die "Invalid audio stream. Container not supported or corrupt";
    }
    
    demuxAudio($audio_type);
    $audio_path = abs_path("$outfile.$audio_type");
    
    postAudio('file',"$audio_path",'spotify','');
    unlink "$outfile.$audio_type" if (-e "$outfile.$audio_type" && $keep == 0);
}

my $in_length = scalar @$input;
my $music_mode;

unless ($in_length > 2) {
    if (@$input[0] =~ m/\.(mp3|m4a|flac|wav|aiff)/) {
	$music_mode = 1;
    }
    elsif (@$input[0] =~ m/\.(mp3|m4a|flac|wav|aiff)/ && @$input[1] =~ m/\.(jpg|jpeg|jfif|png)/) {
	$music_mode = 1;
    }
    elsif (@$input[0] =~ m/\.(jpg|jpeg|jfif|png)/ && @$input[1] =~ m/\.(mp3|m4a|flac|wav|aiff)/) {
	@$input = reverse(@$input);
	$music_mode = 1;
    }
}

foreach my $inarg (@$input) {
    if (-d $inarg) {
	undef $outfile;
	
	opendir(input_dir,"$inarg");
	my @media_files = readdir(input_dir);
	closedir(input_dir);
	
	foreach $infile (@media_files) {
	    next if ($infile !~ m/\.(mp4|mkv|webm|mov|3gp|avi|flv|f4v|mpeg|ogg|wmv|yuv|gif)$/ || $infile =~ m/^\.+$/);
	    $infile = ($inarg =~ m/\/$/)? $inarg . $infile : "$inarg/$infile";
	    
	    my $t0 = time;
	    convertFile();
	    my $t1 = time;
	    my $delta_t = sprintf("%.3f",$t1-$t0);
	    print "\n--------------------------------\nTime elapsed: ",$delta_t," s\n";
	    
	    undef $speed;
	    undef $outfile;
	    $margin = 0;
	}
    }
    elsif (-f $inarg) {
	undef $outfile if ($in_length > 1);
	$infile = $inarg;
	
	if ($break_duration) {
	    removeDuration("$infile");
	}
	elsif ($audio_recog) {
	    recogniseAudio("$infile");
	}
	elsif ($music_mode) {
	    convertMusic(@$input[1]);
	    last;
	}
	else {
	    my $t0 = time;
	    convertFile();
	    my $t1 = time;
	    my $delta_t = sprintf("%.3f",$t1-$t0);
	    print "\n--------------------------------\nTime elapsed: ",$delta_t," s\n";
	}
	undef $speed;
	undef $outfile;
	$margin = 0;
    }
}
