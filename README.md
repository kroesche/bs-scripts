# Borg Backup Scripts

This is my template for my borg backup scripts. I use this instead of borgmatic
or vorta (or whatever) for reasons.

[Borg Backup](https://borgbackup.readthedocs.io/en/stable/)

See [notes about installing borg](#notes-about-installing-borg) below.

## Naming

Naming a project is hard, especially if it needs to live in the namespace of
other utilities on your system. I originally named these scripts like
`borg-backup` but the wording of everything got confusing because it is not the
same as Borg the backup program, even though it uses it.

I decided to use a namespace `bs` which could stand for "borg scripts" or maybe
"backup strategy". So now everything is prefixed with `bs-` which hopefully
avoids confustion with naming everything "borg" ald leaves script names unique
enough to avoid namespace collision. I call the entire package "bs-scripts".

## Installing

Get the package by cloning the repo, or downloading the files or a zip blob
from GitHub.

You can then just use the scripts directly from wherever you put them. Or you
can use the installer script `bs-install` to install them somewhere on your
system. The installer script has help (`-h`). Here is an example if you are in
the same directory as the downloaded/cloned package:

    sudo ./bs-install -s . -d /usr/bin/local -m

This will copy the scripts from your CWD to `/usr/local/bin`. This is good
place because it is probably already on your PATH and makes the backup scripts
available to all account. But it probably requires `sudo` privelege escalation
to write files there.

The `-m` is optional and will install man pages.

Other locations you could use (and don't need sudo):

- `~/bin`
- `~/.local/bin`

## Using

Edit `bs-repo.cfg` to put the correct values for `BORG_NNNN` variables.

Test the script with:

    ./bs-backup -t example

Which should show a dry run without backing anything up. Or:

    ./bs-backup -b example

which will perform an actual backup up of these scripts (you can delete the
test backup later).

## Customize

Make your own backup set by copying `bs-set-example.cfg` to your own set
name. For example `bs-set-mybackup.cfg`. Then edit it to customize it for
your backup set. Then invoke with:

    ./bs-backup -b mybackup

## Launch Agent

There is a script `./bs-agent` that will install a LaunchAgent (on MacOS) to
run a backup on a schedule.

## Logs

There is a script `./bs-logs` to help with examining and managing the log
file.

## Verify Backups

Besides using `borg --check` which you should do on occassion, there is a
script, `./bs-verify` to help with verifying the integrity of a backup.

## Help

Run the script with `-h` to get some help.

    ./bs-backup -h
    ./bs-agent -h
    ./bs-logs -h
    ./bs-verify -h

Also, there are man pages in `man/` directory. You can install these on your
system. See the script `bs-install-man`. Then you can use man to see some
documentation:

    man bs-backup

Or if you don't want to install the man pages, you can just view them directly
like:

    man man/bs-backup.1

There is a top level man page: `man bs-scripts`

## Borg Version

These scripts are assuming the 1.4.x version of borg. I have not tried 2.x yet.

## MacOS Security

MacOS has security that tries to sandbox apps and programs to have access only
to the data they need to function. When you run a program like borg that tries
to read a lot of files, you get asked for permission to grant access to either
specific directories, or full disk access. I already gave my terminal full disk
access so I never encountered this when running borg from the command line. But
when I ran it as a launch agent, I ran into this problem and had to grant it
access to my user folders, so that it can read all the files to back them up.

To make sure this is not going to cause a problem for the launch agent, after
installing a launch agent for a backup set, you can do a test run.

    bs-agent -r mybackup

This will cause it to start running the backup set under launchd, and you will
then see if you are prompted for any access permissions. It's better to get it
out of the way now rather than have your automated backup stall halfway through
when you are not around to fix it.

## Notes About Installing Borg

This applies to MacOS (**x86**)for now. I originally installed borg backup using
[MacPorts](https://www.macports.org). When I ran from command line there was
no problem reading all the files. This is because I previously gave terminal
"full disk access" permission. When run under launchd (as a launch agent), I
was repeatedly prompted to give "python3" access to this or that folder. But I
wanted to authorize "borg" not python3. With this approach, every python3
program would have full disk access. I think the reason this happens is because
the MacPorts-installed borgbackup uses the macports managed python3 to run.

*(Added note: I also installed the homebrew version and had the same
side-effect - Mac security asking me to approve python to have disk access)*

Next, I downloaded the borg prebuilt binary from the
[releases page](https://github.com/borgbackup/borg/releases). I downloaded the
single file binary `borg-macos1012` and installed it in `/usr/local/bin` so it
would be on my path. This worked fine, but every time borg started, even just
`borg --version` it would take 10-20 seconds to start. This was an annoyance.
The reason is because borg is really a python program built with pyinstaller.
For the single file binary, it is uncompressing all of the program and a python
interpreter every time it is invoked. This goes into a temporary folder and
disappears when the program terminates.

Then, from the releases page, I downloaded `borg-macos1012.tgz`, and unzipped
it. This is the same program, but in a set of folders instead of being all
compressed into a single file. In this case, I put the unzipped `borg-dir` into
`/usr/local/share`, and then symlinked `/usr/local/bin/borg` to the `borg.exe`
in the borg-dir folder. Now I still have `borg` on my path but it runs pretty
much immediately.

BTW in both cases of downloading the binary from the GitHub releases page, I
had to use `xattr` to remove the quarantine attribute from either the single
file, or recursively over the unzipped directory structure.

## Apple Silicon (Mx)

The above does not work on a Mac with Apple silicon like an M1, M2, etc. The
prebuilt binaries only work on x86. Maybe it can be made to work with Rosetta
but I didn't try that.

For my first attempt with an M3 Mac I used homebrew to install borg. This
worked fine when running from the command line. But it required authorizing
"python3"  to various permissions, repeatedly. When trying to run under
launchd, I never could figure what permissions to give that would allow it to
complete a backup. When the backup agent runs, it asks for the various
permissions each time it runs. It doesn't persist the permissions, unlike my
x86 Mac that only required granting permissions once. I don't know if this was
because I was using homebrew instead of MacPorts or the borg prebuilt binary,
or because there is something different about the sandbox and permimssions
model on Apple silicon Mac.

### Solution - Build your own

If borg provided a prebuilt package for Mx Macs, then this would not be
necessary. I created a new script named `bs-install-borg`. This script will
download the borg source from GitHub, set up the python build environment, and
build the package for the host system. This means on M3 Mac, it builds a
package suitable for running on the M3 Mac.

If you want to try this, see the script `bs-install-borg`. There are comments
in the script and there is also a man page for it (see the "help" section above
if you want to use man pages).
