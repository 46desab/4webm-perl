#!/usr/bin/perl
#
# RDEPEND: ffmpeg, SvtVp9EncApp
# 4webm: A simple webm converter script using ffmpeg, SVT-VP9 compatible
########################################################################

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage qw(pod2usage);
use POSIX qw(strftime floor);
use Term::ANSIColor;
use File::Basename;
use Env;
use IPC::Run qw(run timeout);
use File::Copy;
use Win32::Console::ANSI;

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
my $OVERHEAD = 3;

# System variables

my $ffmpeg;
my $ffprobe;
my $ffprobe_output;
my $ffmpeg_path;
my $os = $^O;
my $dir;
my $svtvp9;

$dir = (-l __FILE__)? dirname(readlink(__FILE__)) : dirname(__FILE__);

#Packing all binaries into one, at the cost of having to unpack everything => first start-up always slow
#$dir = "$ENV{PAR_TEMP}\\inc\\$dir";
#vs.
#Pack only the essentials, access the binaries in the PAR_PROGNAME directory => faster, but more files for user to manage.
if ($ENV{PAR_0}) {
    my $env_dir = "$ENV{PAR_PROGNAME}";
    #using a large regex for those who rename the binary file.
    $env_dir =~ s/\\[\w\-\,\;\.\:\#\+\~\´\`\=\{\}\(\)\[\]\&\%\$\§\!]+\.exe$//;
    $dir = "$env_dir\\$dir";
}

if ($os eq "linux") {
    die "This version of 4webm-perl is not compatible with Linux. Please visit the github repository for 4webm-perl and download the correct version for your OS.\n";
}
elsif ($os ne "MSWin32") {
    die "Your operating system ($os) is currently not supported.";
}

# Global variables

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
my $svt_args;
our $infile;
our $aspect;
our $rc_mode;
my $speed;
my $keep_raw;
my $crop_reference;
my $orig_framerate;
my $framerate;
my $h_resolution;
my $v_resolution;
my $h_limit_resolution = my $v_limit_resolution = 2048;
our $outfile;
my $date = strftime "%d%b%Y_%H-%M-%S", localtime;
my $force;
my $break_limits;
my $break_duration;
our $q_value = 55;
our $encoder_option = "none";

my $pod = my $man = 0;

GetOptions(
    'audio|a:f' => \&setAudio,
    'autocrop:f' => \&setAutoCrop,
    'board|b=s@' => \$board,
    'end|e=s' => \$etime,
    'force|f' => \$force,
    'library|l=s' => \$ffmpeg_path,
    'input|i=s' => \$input,
    'keep' => \$keep_raw,
    'keyframe=i' => \$user_keyspace,
    'legacy' => \&setEncoder,
    'margin|m=f' => \$margin,
    'output|o=s' => \$outfile,
    'quality|q=s' => \$quality,
    'q-value=i' => \$q_value,
    'rate-control=i' => \$rc_mode,
    'remove-limits' => \$break_limits,
    'remove-duration' => \$break_duration,
    'start|s=s' => \$stime,
    'svt-vp9|t' => \&setEncoder,
    'speed|v=i' => \$speed,
    'tune=i' => \$tune,
    'extra|x=s' => \$extra_args,
    'extra-svt=s' => \$svt_args,
    'help' => \$pod,
    'man' => \$man
    ) or die colored(["bright_red"],"Unrecognised option(s)!")," You can access the help/usage screen by using -h\n";

die colored(["bright_red"], "Insufficient arguments!")," Type 4webm -h for a short usage screen.\nExiting...\n" unless ($input || $pod || $man);

pod2usage(-sections => "SYNOPSIS", -input => "$dir\\usage.pod") if $pod;
pod2usage(-perldocopt => "-o man",-verbose => 2, -input => "$dir\\usage.pod") if $man;

die colored(["bright_red"],"Input file/directory not found or empty!"),"\n" unless (-f $input || -s $input || -d $input);
die colored(["bright_red"],"File not found!")," Check file handle.\n" if (-f $input && $input !~ m/\.\w{2,4}$/);

$ffmpeg = "ffmpeg";
$ffprobe = "ffprobe";
if ($ffmpeg_path) {
    print "Specified ffmpeg \$DIR = $ffmpeg_path";
    $ffmpeg = "$ffmpeg_path\\ffmpeg";
    $ffprobe = "$ffmpeg_path\\ffprobe";
}
else {
    for my $path (split(":", $ENV{PATH})) {
	if (-f "$path\\$ffmpeg" && -x _) {
	    $ffmpeg = "ffmpeg";
	    $ffprobe = "ffprobe";
	    $ffmpeg_path = "$path\\$ffmpeg";
	    last;
	}
    }
    unless ($ffmpeg_path) {
    	if ($ENV{PAR_0}) {
	    print "4webm-perl, bundled libraries.\n";
	}
	else {
	    print "ffmpeg not found in \$PATH nor specified with --library\nUsing bundled executables.\n";
	}
	$ffmpeg = "$dir\\ffmpeg\\bin\\ffmpeg";
	$ffprobe = "$dir\\ffmpeg\\bin\\ffprobe.exe";
    }
}
$svtvp9 = "$dir\\SVT-VP9\\SvtVp9EncApp";

sub exitScript {
    exit($_[0]) unless ($force);
}

sub getOutfile {
    my $infile = shift;
    unless ($outfile) {
	($outfile) = $infile =~ m/(.*)\.\w{2,4}/s;
	$outfile = "$outfile\_$date";
    }
    return $outfile;
}

sub proceed {
    my $affirm = "y";
    unless ($force) {
	print "Proceed? [",colored(["bright_green"],"y"),"/",colored(["bright_red"],"n"),"]: ";
	$affirm = <STDIN>;
	chomp $affirm;
    }
    my $encoder_option = $_[0];

    if (($affirm eq "y" || $affirm eq "Y") && $encoder_option eq "fix") {
	print "Re-encoding audio\n";
	encodeAudio("$outfile" . ".webm");
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
	print colored(["bright_yellow"],"\nExiting..."),"\n";
	exitScript(1);
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
	
    print colored(["bright_magenta"],"\nPass 1/2:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -c:v $libcv -b:v "$bitrate"K $keyspace $keyintmin -pass 1 -quality good -speed 4 $extra_args -an -f rawvideo -y NUL);
    print colored(["bright_magenta"],"\nPass 2/2:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -c:v $libcv -b:v "$bitrate"K $keyspace $keyintmin -pass 2 -quality $quality -speed $speed $extra_args $audio_opts -row-mt 1 -map_metadata -1 -y "$outfile".webm);
    unlink "ffmpeg2pass-0.log";
    checkFileSize("$outfile.webm");
}

sub encodeAudio {
    my $audio_file = $_[0];
    my $arg2 = ($_[1]) ? $_[1] : "";
    print colored(["bright_magenta"],"Pass 1/1:"),"\n";
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$infile" $stime $etime -vn $audio_opts "$infile"_audio.opus);
    qx($ffmpeg -hide_banner -loglevel error -stats -i "$audio_file" -i "$infile"_audio.opus -c:v copy $audio_opts -map 0:v:0 $arg2 $aspect -map 1:a:0 -shortest -map_metadata -1 -y "$outfile"_remux.webm);
    unlink "$infile\_audio.opus";
}
    
sub encodeSvtVp9 {
    
    $bitrate = floor($bitrate * 1000);
    
    unless ($rc_mode) {
	$rc_mode = ($bitrate > 100000)? "1" : "2";
    }
    
    my $bsfv = "-bsf:v vp9_superframe";
    my $max_rate = $bitrate * 1.25;
    my $buf_size = $bitrate * 0.25;
    my $keyspace = ($framerate == 29.97 || $framerate == 59.94)? 239 : $framerate * 8 - 1;
    my $numerator = $framerate * 100;
    my $denominator = 100;

    if ($user_keyspace) {
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
    
    print colored(["bright_magenta"],"\nDemuxing, Stage 1/2:"),"\n";
    run("$ffmpeg -hide_banner -loglevel error -stats -i \"$infile\" -pix_fmt yuv420p $stime $etime $extra_args -y raw.yuv") unless (-e "raw.yuv" && $keep_raw);
    print colored(["bright_magenta"],"\nEncoding, Stage 2/2:"),"\n";
    run("$svtvp9 -i raw.yuv -w $h_resolution -h $v_resolution -intra-period $keyspace -fps-num $numerator -fps-denom $denominator -rc $rc_mode -tbr $bitrate -min-qp 0 -max-qp 60 -tune $tune -enc-mode $speed \"$svt_args\" -b \"$outfile.ivf\"");
    unlink "raw.yuv" unless ($keep_raw);

    if ($audio) {
	print "\n",colored(["bright_magenta"],"Muxing audio"),"\n";
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

sub checkFileSize {
    my $outfile_size = -s $_[0];
    $outfile_size = $outfile_size / 2**20;
    
    if ($outfile_size > $file_size_limit) {
	my $delta = $outfile_size - $file_size_limit;
	($bitrate,$c_bitrate,$nominal_rate) = $delta->$eq_bitrate;
	print "\nThe output file size is: ",colored(["bright_red"],"$outfile_size")," MiB, which is larger than the max. permissible filesize of $file_size_limit MiB\n";
	
	if ($audio) {
	    $arate_adjust = $arate_adjust - $nominal_rate - 1;
	    
	    if ($arate_adjust > 32 && $libcv ne "svt-vp9") {
		$audio_opts = "-c:a $libca -b:a " . $arate_adjust . "K";
		print "Re-encode audio at $arate_adjust kbps to reduce the file size?";
		proceed("fix");
	    }
	    else {
		$margin = $margin + $nominal_rate + 1;
		print colored(["bright_yellow"],"Fix attempt not possible.")," resulting audio bitrate would drop below threshold of 32 kbps. Rerun with \"--margin $margin\".\n";
		exitScript(2);
	    }
	}
	else {
	    $margin = $margin + $nominal_rate + 1;
	    print "Rerunning with \"--margin $margin\" may bring the file size back within limits.\n";
	    exitScript(2);
	}
    }
    elsif ($outfile_size == 0) {
	die colored(["bright_red"],"\nEncoding error:")," No output file was generated\n";
    }
    else {
	my $delta = $file_size_limit - $outfile_size;
	($bitrate,$c_bitrate,$nominal_rate) = $delta->$eq_bitrate;
	$margin = $margin - $nominal_rate + 1;
	print "\nThe output file size is: ",colored(["bright_green"],"$outfile_size")," MiB\n";
	
	if ($nominal_rate > $LOWLIMIT && $outfile_size != 0) {    
	    print "It may be possible to increase quality while staying within limits by setting \"--margin $margin\".\n";
	    if ($libcv eq "svt-vp9") {
		print "This is advisable for SVT-VP9 encoded media, if the output file size is significantly below limits.\n";
	    }
	    exitScript(2);
	}
	exitScript(0);
    }
}

sub setAutoCrop {
    $crop_reference = ($_[1] != 0)? $_[1] : 1;
}

sub getAutoCrop {
    my $crop_detect = qx(ffmpeg -i "$infile" -vf cropdetect -t $crop_reference -f null - 2>&1);
    ($crop_detect) = $crop_detect =~ m/(crop=\d+:\d+:\d+:\d+)(?!.*crop=\d+:\d+:\d+:\d+)/s;

    if ($extra_args) {
	$extra_args = $extra_args . "," . $crop_detect;
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
	$OVERHEAD = 5;
	$libcv = "svt-vp9";
    }
}

@$board = split(/,/,join(",",@$board));

if (@$board[0] eq "wsg") {
    $file_size_limit = 6;
    $max_dur = 300;
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
    $board_audio = @$board[1] // 0;
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
    die colored(["bright_red"],"Custom board parameters incomplete.")," Required parameters: Max. file size in MiB, max. duration in s\n" unless ($file_size_limit && $max_dur);
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

sub getProbe {
    my $probe_file = shift;
    return qx($ffprobe -hide_banner -stats -i "$probe_file" 2>&1);
}

sub getFramecount {
    my $framecount = qx(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$infile" 2>&1);
    return ($orig_framerate == $framerate)? $framecount : floor($framecount * $framerate / $orig_framerate);
}

sub checkAudio {
if ($audio && $board_audio) {
    $audio_state = "true";
    $audio_opts = "-c:a $libca -b:a " . $arate_adjust . "K";
    ($arate) = $ffprobe_output =~ m/^.*fltp, (\d+)/s;
    unless ($arate) {
	$arate = 128;
    }
}
elsif ($audio) {
    die colored(["bright_red"],"\nBoard limit:")," The selected board does not support audio. Change board, disable audio or force encoding by setting -b/--board @$board,1\n";
}

}

sub getDuration {
    my $ffprobe_output = shift;
    my $duration;
    my ($ffprobe_duration) = $ffprobe_output =~ m/^.*Duration: (\d+:\d+:\d+\.\d+)/s;
    my @ffprobe_tdur = split(/:/,$ffprobe_duration);
    $ffprobe_duration = 3600 * $ffprobe_tdur[0] + 60 * $ffprobe_tdur[1] + $ffprobe_tdur[2];
    
    if ($stime && $etime) {
	@start = split(/:/,$stime);
	@end = split(/:/,$etime);
	$duration = 3600 * ($end[0] - $start[0]) + 60 * ($end[1] - $start[1]) + ($end[2] - $start[2]);
	$stime = "-ss $stime";
	$etime = "-to $etime";
    }
    elsif (defined $stime && not defined $etime) {
	@start = split(/:/,$stime);
	@end = @ffprobe_tdur;
	$duration = 3600 * ($end[0] - $start[0]) + 60 * ($end[1] - $start[1]) + ($end[2] - $start[2]);
	$stime = "-ss $stime";
	$etime = "";
    }
    elsif (defined $etime && not defined $stime) {
	@start = (0,0,0.0);
	@end = split(/:/,$etime);
	$duration = 3600 * ($end[0] - $start[0]) + 60 * ($end[1] - $start[1]) + ($end[2] - $start[2]);
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
    (my $c_bitrate) = $ffprobe_output =~ m/^.*bitrate: (\d+)/s;
    my $nominal_rate = getBitrate($target,$duration);
    my $nominal_rate_adj = $nominal_rate - $arate_adjust;
    
    my $bitrate = ($nominal_rate < $c_bitrate)? $nominal_rate_adj - $margin - $overhead : $c_bitrate - $margin;
    return ($bitrate,$c_bitrate,$nominal_rate);
}

sub setFramerate {
    ($orig_framerate) = $ffprobe_output =~ m/(\d+\.?\d+) tbr/;
    unless ($orig_framerate) {
	($orig_framerate) = $ffprobe_output =~ m/(\d+\.?\d+) fps/;
    }
    
    if ($extra_args =~ m/fps/) {
	($framerate) = $extra_args =~ m/fps=(\d+(\.\d+)?)/;
    }
    else {
	$framerate = $orig_framerate;
    }
}

sub checkResolution {
my @resolution  = $ffprobe_output =~ m/(\d{2,4})x(\d{2,4})/;
$h_resolution = $resolution[0];
$v_resolution = $resolution[1];
my $aspect_ratio = $h_resolution/$v_resolution;

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
    die "The video resolution exceeds the maximum of ",colored(["bright_yellow"],"2048x2048"),". Please scale or crop the input via -ex/--extra.\n";
}

if ($libcv eq "svt-vp9" && ($h_resolution % 8 != 0 || $v_resolution % 8 != 0)) {
    $libcv = "libvpx-vp9";
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
    
sub printMediaInfo {
print color("bright_magenta");
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
VIDEO FRAMERATE:		$framerate fps
CURRENT TOTAL BITRATE:		$c_bitrate kbps
MAX. PERMISSIBLE BITRATE: 	$nominal_rate kbps
SELECTED VIDEO BITRATE:		$bitrate kbps
EOF
if ($extra_args) {
    print "FFMPEG ARGUMENTS:		$extra_args\n";
}
if ($break_limits || $user_keyspace) {
    print "FRAME COUNT:                    ",getFramecount(),"\n";
}
print <<EOF;
===================================================================================================
EOF
print color("reset");
}

sub convertFile {
    $outfile = getOutfile($infile);
    $ffprobe_output = getProbe($infile);
    checkAudio();
    $duration = getDuration($ffprobe_output);
    ($bitrate,$c_bitrate,$nominal_rate) = $file_size_limit->$eq_bitrate;
    getAutoCrop if ($crop_reference);
    setFramerate();
    checkResolution();
    setOptimisations();
    printMediaInfo();
    proceed($encoder_option);
}

if (-d $input) {
    undef $outfile;
    
    opendir(input_dir,"$input");
    my @media_files = readdir(input_dir);
    closedir(input_dir);
    
    foreach $infile (@media_files) {
	next if ($infile !~ m/\.(mp4|mkv|webm|mov|3gp|avi|flv|f4v|mpeg|ogg|wmv|yuv|gif)$/ || $infile =~ m/^\.+$/);
	$infile = ($input =~ m/\/$/)? $input . $infile : "$input/$infile";
	convertFile();
	undef $speed;
	undef $outfile;
	$margin = 0;
    }
}
elsif (-f $input) {
    $infile = $input;
    ($break_duration)? removeDuration("$infile") : convertFile();
}
