# 4webm-perl

4webm-perl: A simple 4chan .webm conversion script.

## "Installation"

### Linux

Just chuck it into a dedicated script folder (ideally in `$PATH`) or have it in any folder that contains media to be converted and make it executable (`$ chmod u+x 4webm.plx`). Alternatively, download the pre-configured binary. (Or use [my bash script](https://www.codeberg.org/based64/4webm "4webm-bash"))

Requirements: perl (should be installed by default on most distros), ffmpeg, SVT-VP9 (optional)

### Windows

**With perl installed:** Just chuck it into a dedicated script folder (ideally in `$PATH`) or have it in any folder that contains media to be converted. Run the script with `> perl 4webm.plx`.

Requirements: perl, ffmpeg, SVT-VP9 (optional)

**With the standalone binary**: Just chuck it into a dedicated folder (ideally in `$PATH`) or have it in any folder that contains media to be converted. Run the binary via the command prompt: `> 4webm.exe` or just `> 4webm`.

Requirements: none.

## Usage

The absolute minimum command required to transcode media into 4chan compatible webms is:

```bash
$ ./4webm.plx -i input.mp4
```
or
```bash
$ ./4webm.plx -i ~/path/to/your/files
```
Unless the script is batch converting or the `-o` flag is set, the output file name will default to `inputfilename_DATE_TIME.webm`. If a different max. file size, duration and audio compatibility is desired, specify a board and enable the audio flag:

```bash
$ ./4webm.plx -i input.mp4 -b wsg -a
```
A "complete" example:

```bash
$ ./4webm.plx -i input.mp4 -b wsg -a 128 -m 10 -q best -v 0 -s 00:00:10.500 -e 00:01:19.690 -x "-vf eq=saturation=1.1,scale=-1:720 -aspect 16:9"
```

Or running in "batch mode":

```bash
$ ./4webm.plx -i /path/to/files -b wsg -a -f
```

Basic flags:
* **(REQUIRED)** `-i input.mp4` specifies the **input file**
* `-b wsg` specifies **/wsg/** as the target board. Leaving this flag out will default the board setting to **/g/** (which shares the same limits with basically 90% of all boards).
* `-a 128` enables **audio** and sets the desired audio bitrate to **128** kb/s. Without specifying a bitrate, it defaults it to 96 kb/s
* `-m 10` sets the video bitrate **margin** to **10** kb/s, this margin is subsequently subtracted[^1] from the calculated bitrate and can be used to decrease file sizes, e.g., if the script failed to produce a webm within board limits (which is rare, but can happen) or to increase quality if the script produced a file that's significantly below limits
* `-q best` sets the **quality** setting of *libvpx-vp9* to **best**, users can choose from **realtime**, **good** and **best**. This setting affects compression efficiency
* `-v 0` sets the **speed** setting of *libvpx-vp9* to 0, users can set this in the range **0-5** (0-8 for realtime quality) with 0 having the best compression and 5 the lowest
* `-s 00:00:10.500 -e 00:01:19.690` sets the **start** and **end** points. Users can choose to use none, either one of them or both.
* `-x "-vf eq=saturation=1.1,scale=-1:720 -aspect 16:9"` this specifies additional settings to be handed over to *ffmpeg*, for further reference, [consult the ffmpeg manuals.](https://trac.ffmpeg.org/wiki "ffmpeg documentation")

* (not shown) `-l` changes the video and audio codices to *libvpx* (VP8) and *libvorbis*. This also means that `-q` and `-v` are no longer functional. This should only be used for compatibility (**legacy**) purposes.

* `-f` skips user confirmation and **forces** the script to proceed. Can be used in conjunction with `-i /path/to/files` to convert a batch of files

* (experimental) `-t` changes the VP9 encoder to SVT-VP9. Requires SvtVp9EncApp in `$PATH` or locally. Skips two-pass encoding[^2]

The help screen explains all flags and can be accessed via `$ ./4webm.plx --man`. A short help page can be accessed via `$ ./4webm.plx -h`.

## Default behaviour

The script determines a suitable total bitrate for a two pass encoding and additionally ensures that all board limits are met (i.e. max. file size, duration and resolution). If the input file is already within board limitations, the output file will closely match it in both size and quality. Should the input file exceed board limitations, the max. permissible bitrate for the output will be automatically selected.

The script also suggests a value for the margin setting `-m`, should the output be above/significantly below board limits. Alternatively, if audio was enabled, a lower audio bitrate is determined which reduces the file size (this option only re-encodes audio and is thus significantly faster than re-encoding the video again). 

There are currently no flags to optimise for bandwidth or storage space, this can be worked around by setting a high margin `-m` or setting the target board to /bant/: `-b bant` (2MiB limit).

When running in batch mode, any flags that control media parameters will affect all files equally.

## Alternative encoder: SVT-VP9

Running the script with `-t` enabled sets the VP9 encoder to SVT-VP9. Optimisations for SvtVp9EncApp are automatically determined. Using SVT-VP9 instead of libvpx-vp9 will result in a significant encoding speed boost of **10x-100x** (depending on `-v` setting and system specs). Tradeoffs are a *reduction* in *compression efficiency* and *visual quality* at lower bitrates. Additionally, only a single pass can be made, which is less efficient than a two-pass approach.

SVT-VP9 tends to produce files with bitrates slightly below the target bitrate, which means that multiple passes with different margin settings may be advisable in order to achieve the highest possible quality (a tradeoff for the high encoding speed).

A precompiled static binary (for linux x86-64) is supplied in the folder SVT-VP9 with its accompanying licence and notices. These binaries are supplied as is.

The binaries are compiled with AVX2 support. If AVX2 isn't supported on your system, it may be advisable to recompile SVT-VP9 locally. Please check [the official SVT-VP9 repository](https://github.com/OpenVisualCloud/SVT-VP9) for more information.

The pre-configured binaries include the [ffmpeg builds by BtbN](https://github.com/BtbN/FFmpeg-Builds) with its accompanying licences and notices.

[^1]: Currently, a positive margin value reduces the total bitrate, while a negative value increases it. This should probably be changed, but for now, it'll work.

[^2]: SVT-VP9 has a known bug which causes the encoder to simply freeze. Stopping the script and re-running it fixes this. Specifying `--keep` will prevent the script from discarding the raw yuv file and skip the demuxing step.
