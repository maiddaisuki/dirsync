# dirsync.tcl

`dirsync.tcl` is a TCL script to sync contents of multiple directories.

This script can be compared to

```shell
cp -pRu $srcdir -t $destdir
```

except that `dirsync.tcl` tries to do more than just copy files:

- it removes files and directories from `destdir` which are no longer present
  in `srcdir`
- allows you to specify wildcards for files and directories which must be
  ignored in either `srcdir` or `destdir`
- allows you to specify files and directories which must be copied to `destdir`,
  even if they are up to date with `srcdir`

## Invocation

Run as

```shell
./dirsync.tcl [OPTIONS] ...
```

or

```shell
tclsh dirsync.tcl [OPTIONS] ...
```

The latter is recommended on Windows.

### Options

| Option            | Description                                       |
| ----------------- | ------------------------------------------------- |
| --destdir=DIRNAME | Destination directory. This option is cumulative. |
| --srcdir=SRCDIR   | Source directory.                                 |
| --no-config       | Do not read any config files.                     |
| --verbose         | Print what script is doing.                       |
| --debug           | Print even more messages.                         |
| --dry-run         | Do not perform any action. Implies `--verbose`.   |

If `--srcdir` option is not specified, the current directory is assumed to be
`srcdir`.

## Config Files

Unless `--no-config` option is passed, the script will attempt to read
config files from `srcdir/.dirsync` directory.

### Destinations

The script will look for two files:

1. `dest-PLATFORM.list`, where `PLATFORM` is value of TCL variable
   `tcl_platform`
2. `dest.list`

The first one found will be read.

`NOTE:` value of `tcl_platform` on Cygwin is `unix`.

This file must contain list of directory names, one per line.
See [Syntax](#syntax).

### Force Copy

The script will look for file named `force-copy.list` and read it if it exists.

This file specified list of wildcards (see [Syntax](#syntax)) for files and
directories which must always be copied from `srcdir` to `destdir`,
even if they are up to date.

### Source Ignore

The script will look for file named `src-ignore.list` and read it if it exists.

This file specified list of wildcards (see [Syntax](#syntax)) for files and
directories which must be ignored in `srcdir`. Those files and directories
will not be copied from `srcdir`, and if already present in `destdir`, ignored.

### Destination Ignore

The script will look for file named `dest-ignore.list` and read it if it exists.

This file specified list of wildcards (see [Syntax](#syntax)) for files and
directories which must be ignored in `destdir`. Those filesa and directories
will not be removed from `destdir` if they are not present in `srcdir`.

### Syntax

Config files are plain text files, specifying one item per line:

- empty lines (which contain only whitespace) are ignored
- lines where first non-whitespace character is `#` are comments and ignored

#### Wildcards

The script understands four types of wildcards:

`filename-relative`. The wildcard is matched against full file name constructed
relative to `srcdir`.

`filename-basename`. The wildcard is matched against file name's basename,
that is, directory part is ignored.

`dirname-relative`. The wildcard is matched against full directory name
constructed relative to `srcdir`.

`dirname-basename`. The wildcard is matched against directory name's basename,
that is, directory part is ignored.

In order to mark wildcard as `*-relative`, prepend it with `/` character.  
In order to mark wildcard as `dirname-*`. append `/` character to it.

Example:

```plain
# filename-relative
/some/dir/*.log

# filename-basename
*.log

# dirname-relative
/some/dir/.git/

# dirname-basename
.git/
```

Note that `dirname-relative` `/dirname/` and `filename-relative` `/dirname/*`
are not the same. The latter will ignore all files but not directories under
`dirname/` .
