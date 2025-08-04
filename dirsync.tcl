#!/bin/env tclsh

#  Copyright 2025 Kirill Makurin
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

##
# ::Msg
#
# Function to write messages to streams
#
namespace eval Msg {
  # Print a note message $text to $stream
  #
  proc Note {text {stream stdout}} {
    puts $stream "NOTE: $text"
  }

  # Print a warning message $text to $stream
  #
  proc Warn {text {stream stderr}} {
    puts $stream "WARNING: $text"
  }

  # Print an error message $text to $stream
  #
  proc Error {text {stream stderr}} {
    puts $stream "ERROR: $text"
  }

  # Print an error message $text to $stream and exit
  #
  proc Fatal {text {stream stderr}} {
    Error $text $stream
    exit 1
  }
}

##
# ::Options
#
# This namespace defines functions to parse command line arguments and
# access script's options
#
namespace eval Options {
  # --no-config
  set Options(config) 1
  # --debug
  set Options(debug) 0
  # --destdir
  set Options(destdirs) [list]
  # --dry-run
  set Options(dry) 0
  # --srcdir
  set Options(srcdir) [pwd]
  # --verbose
  set Options(verbose) 0

  ##
  # Parse $argv and set Options()
  #
  proc Set {} {
    # Access $argv list
    upvar argv argv
    # Access namespace variables
    variable Options

    foreach arg $argv {
      if [string equal $arg "--no-config"] then {
        set Options(config) 0
        continue
      }

      if [string equal $arg "--debug"] then {
        set Options(debug) 1
        continue
      }

      if [string equal $arg "--dry-run"] then {
        set Options(dry) 1
        set Options(verbose) 1
        continue
      }

      if [string equal $arg "--verbose"] then {
        set Options(verbose) 1
        continue
      }

      if [string match "--destdir=*" $arg] then {
        set value [regsub -- "^--destdir=(.*)$" $arg {\1}]
        set Options(destdirs) [lappend Options(destdirs) $value]
        continue
      }

      if [string match "--srcdir=*" $arg] then {
        set value [regsub -- "^--srcdir=(.*)$" $arg {\1}]
        set Options(srcdir) $value
        continue
      }

      Msg::Fatal "$arg: invalid option"
    }

    return -code ok
  }

  ##
  # Get value of Options($option)
  #
  proc Get {option} {
    # Access namespace variables
    variable Options

    return $Options($option)
  }
}

##
# ::Config
#
# This namespace defines functions to read config files.
#
namespace eval Config {
  # Source directory to operate on
  #
  variable Srcdir

  # Contains config files to read
  #
  # Files(Dest)
  #   list of destination directories
  #
  # Files(SrcIgnore)
  #   list of patterns specifying files and directories
  #   to be ignored in the source directory
  #
  # Files(DestIgnore):
  #   list of patterns specifying files and directories
  #   to be ignored in the each destination directory
  #
  # Files(ForceCopy):
  #   list of patterns specifying files and directories
  #   which will be always synced with source directory
  #
  variable Files

  # Following arrays hold lists of patterns read from files listed in Files()
  #
  # Each array has 4 members:
  #
  # FileBasename:
  #   a file name which must be matched against file's basename
  #
  # FileAbsolute:
  #   a file name which must be matched against full filename relative source
  #   directory's root
  #
  # DirBasename:
  #   a directory name which must be matched against directory's basename
  #
  # DirAbsolute:
  #   a directory name which must be matched against full directory name
  #   relative to source directory's root
  #
  variable Destdirs
  variable DestIgnore
  variable SrcIgnore
  variable ForceCopy

  ##
  # Verify that Options::Options(srcdir) is a valid source directory
  # Populate Files() array with names of config files
  #
  proc Init {} {
    # Access global variables
    global tcl_platform
    # Access namespace variables
    variable Files
    variable Srcdir
    variable Destdirs
    variable DestIgnore
    variable SrcIgnore
    variable ForceCopy

    # source directory
    set srcdir [Options::Get srcdir]

    if ![file exists $srcdir] then {
      Msg::Fatal "$srcdir: directory does not exist"
    } elseif ![file isdirectory $srcdir] then {
      Msg::Fatal "$srcdir: not a directory"
    }

    # Get absolute name of $srcdir
    set Srcdir [file normalize $srcdir]
    # Directory where config files should reside
    set datadir ""

    # Initialize Files() array
    set Files(Dest) ""
    set Files(DestIgnore) ""
    set Files(SrcIgnore) ""
    set Files(ForceCopy) ""

    # User can use --no-config to prevent reading any config files
    if [Options::Get config] then {
      set datadir [file join $Srcdir .dirsync]
    }

    if [file exists $datadir] then {
      if ![file isdirectory $datadir] then {
        Msg::Fatal "$datadir: not a directory"
      }

      # Platform-specific destination list
      set dest_platform [file join $datadir dest-$tcl_platform(platform).list]
      # Generic destination list
      set dest_noplatform [file join $datadir dest.list]

      # Always prefer platform-specific one if it exists
      if [file exists $dest_platform] then {
        set Files(Dest) $dest_platform
      } elseif [file exists $dest_noplatform] {
        set Files(Dest) $dest_noplatform
      }

      set Files(DestIgnore) [file join $datadir dest-ignore.list]
      set Files(SrcIgnore) [file join $datadir src-ignore.list]
      set Files(ForceCopy) [file join $datadir force-copy.list]
    }

    return -code ok
  }

  ##
  # Read destination directories listed in Files(Dest)
  #
  # This function aborts execution of the script if no existing destination
  # directories specified
  #
  proc Destdir {} {
    # Access global variables
    global options
    # Access namespace variables
    variable Files
    variable Destdirs

    # Put destination directories specified with --destdir to the front
    set Destdirs [Options::Get destdirs]

    if [file exists $Files(Dest)] then {
      try {
        set stream [open $Files(Dest)]
      } on error {msg} {
        Msg::Fatal $msg
      }

      while {[gets $stream line] >= 0} {
        set line [string trim $line]

        # Skip over empty lines
        if "[string length $line] == 0" then continue
        # Skip over comments
        if [string match {#*} $line] then continue

        # Skip non-existing destinations
        if ![file exists $line] then {
          if [Options::Get verbose] {
            Msg::Note "$line: skipping non-existing destination"
          }
          continue
        }

        # Convert to absolute name of destination directory
        set destdir [file normalize $line]

        if ![file isdirectory $destdir] then {
          Msg::Warn "$destdir: destination is not a directory"
          continue
        }

        set Destdirs [lappend Destdirs $destdir]
      }

      close $stream
    }

    if "[llength $Destdirs] == 0" then {
      Msg::Note "no existing destination directory has been specified"
      Msg::Note "exiting..."
      exit 0
    }

    return -code ok
  }

  ##
  # Read config file Files($config)
  # Each line read is stored in $config list
  #
  proc Read {config} {
    # Access variables in namespace
    variable Files
    # Access array $config in namespace
    namespace upvar ::Config $config array

    # Initialize $array
    set array(FileBasename) [list]
    set array(FileAbsolute) [list]
    set array(DirBasename) [list]
    set array(DirAbsolute) [list]

    # Files($config) does not exist
    if ![file exists $Files($config)] then {
      return -code ok
    }

    if ![file readable $Files($config)] then {
      Msg::Fatal "$Files($config): file exists but cannot be read"
    }

    try {
      set stream [open $Files($config) r]
    } on error {msg} {
      Msg::Fatal $msg
    }

    while {[gets $stream line] >= 0} {
      set line [string trim $line]
      # Skip over empty lines
      if "[string length $line] == 0" then continue
      # Skip comments
      if [string match {#*} $line] then continue

      if [string match -nocase {/*/} $line] then {
        set pattern [regsub -- {^/(.*)/$} $line {\1}]
        set array(DirAbsolute) [lappend array(DirAbsolute) $pattern]
      } elseif [string match -nocase {*/} $line] then {
        set pattern [regsub -- {^(.*)/$} $line {\1}]
        set array(DirBasename) [lappend array(DirBasename) $pattern]
      } elseif [string match -nocase {/*} $line] then {
        set pattern [regsub -- {^/(.*)$} $line {\1}]
        set array(FileAbsolute) [lappend array(FileAbsolute) $pattern]
      } else {
        set array(FileBasename) [lappend array(FileBasename) $line]
      }
    }

    close $stream

    return -code ok
  }

  ##
  # Check if $filename matches any pattern in $config($type) list
  #
  proc Fnmatch {filename config type} {
    # Access array $config
    namespace upvar ::Config $config array

    foreach pattern $array($type) {
      if [string match -nocase $pattern $filename] {
        return 1
      }
    }

    return 0
  }
}

##
# ::Node
#
# This namespace defines functions to manipulate a pseudo type "Node::Dir"
# and "Node::File" which represent a directory and a file respectively
#
namespace eval Node {
  ##
  # ::Node::File
  #
  # Pseudo type "Node::File" which represents a file
  #
  # Fields:
  #
  # Filename:
  #   file name
  #
  # ForceCopy:
  #   force copy flag
  #
  # Ignore
  #   ignore flag
  #
  namespace eval File {
    # List index of each field
    set Fields(Filename) 0
    set Fields(ForceCopy) 1
    set Fields(Ignore) 2

    ##
    # Initialize and return an object of pseudo type "Node::File"
    #
    proc Init {filename} {
      # Access namespace variables
      variable Fields

      # Initialize empty node
      set node [list]

      set node [linsert $node $Fields(Filename) $filename]
      set node [linsert $node $Fields(ForceCopy) 0]
      set node [linsert $node $Fields(Ignore) 0]

      return $node
    }

    ##
    # Get value of Filename field from "Node::File" object $node
    #
    proc GetFilename {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node file

      return [lindex $file $Fields(Filename)]
    }

    ##
    # Set ForceCopy field of a "Node::File" object to $value
    #
    proc SetForceCopy {node {value 1}} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node file

      lset file $Fields(ForceCopy) $value
    }

    ##
    # Get value of ForceCopy field from "Node::File" object $node
    #
    proc GetForceCopy {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node file

      return [lindex $file $Fields(ForceCopy)]
    }

    ##
    # Set Ignore field of a "Node::File" object to $value
    #
    proc SetIgnore {node {value 1}} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node file

      lset file $Fields(Ignore) $value
    }

    ##
    # Get value of Ignore field from "Node::File" object $node
    #
    proc GetIgnore {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node file

      return [lindex $file $Fields(Ignore)]
    }
  }

  ##
  # ::Node::Dir
  #
  # Pseudo type "Node::Dir" which represents a directory
  #
  # Fields:
  #
  # Dirname:
  #   directory name
  #
  # ForceCopy:
  #   force copy flag
  #
  # Ignore
  #   ignore flag
  #
  # Preserve
  #   preserve flag
  #
  # Files
  #   a list of "Node::File" objects representing each file in this node
  #
  # Dirs
  #   a list of "Node::Dir" objects representing each subdirectory in this node
  #
  namespace eval Dir {
    # List index of each field
    set Fields(Dirname) 0
    set Fields(ForceCopy) 1
    set Fields(Ignore) 2
    set Fields(Preserve) 3
    set Fields(Files) 4
    set Fields(Dirs) 5

    ##
    # Initialize and return an object of pseudo type "Node::Dir"
    #
    proc Init {dirname} {
      # Access namespace variables
      variable Fields

      # Initialize empty node
      set node [list]

      set node [linsert $node $Fields(Dirname) $dirname]
      set node [linsert $node $Fields(ForceCopy) 0]
      set node [linsert $node $Fields(Ignore) 0]
      set node [linsert $node $Fields(Preserve) 0]
      set node [linsert $node $Fields(Files) [list]]
      set node [linsert $node $Fields(Dirs) [list]]

      return $node
    }

    ##
    # Get value of Filename field from "Node::Dir" object $node
    #
    proc GetDirname {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(Dirname)]
    }

    ##
    # Set ForceCopy field of a "Node::Dir" object to $value
    #
    proc SetForceCopy {node {value 1}} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      lset dir $Fields(ForceCopy) $value
    }

    ##
    # Get value of ForceCopy field from "Node::Dir" object $node
    #
    proc GetForceCopy {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(ForceCopy)]
    }

    ##
    # Set Ignore field of a "Node::Dir" object to $value
    #
    proc SetIgnore {node {value 1}} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      lset dir $Fields(Ignore) $value
    }

    ##
    # Get value of Ignore field from "Node::Dir" object $node
    #
    proc GetIgnore {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(Ignore)]
    }

    ##
    # Set Preserve field of a "Node::Dir" object to $value
    #
    proc SetPreserve {node {value 1}} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      lset dir $Fields(Preserve) $value
    }

    ##
    # Get value of Preserve field from "Node::Dir" object $node
    #
    proc GetPreserve {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(Preserve)]
    }

    ##
    # Set Files field of a "Node::Dir" object to $files
    #
    proc SetFiles {node files} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      lset dir $Fields(Files) $files
    }

    ##
    # Get value of Files field from "Node::Dir" object $node
    #
    proc GetFiles {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(Files)]
    }

    ##
    # Set Dirs field of a "Node::Dir" object to $dirs
    #
    proc SetDirs {node dirs} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      lset dir $Fields(Dirs) $dirs
    }

    ##
    # Get value of Dirs field from "Node::Dir" object $node
    #
    proc GetDirs {node} {
      # Access namespace variables
      variable Fields
      # Access $node
      upvar $node dir

      return [lindex $dir $Fields(Dirs)]
    }
  }
}

##
# ::Glob
#
# Convenience functions to perform globbing
#
namespace eval Glob {
  ##
  # Return list of all files with $type in $dirname which match $wildcard
  #
  proc Glob {dirname type wildcard} {
    # Directory names to always remove from the list
    set filter [list "." ".."]

    # Glob
    set list [glob -nocomplain -tails -directory $dirname -types $type $wildcard]

    foreach name $filter {
      set index [lsearch -exact $list $name]
      if "$index != -1" {
        set list [lreplace $list $index $index]
      }
    }

    return $list
  }

  ##
  # Return list of all files in $dirname
  #
  proc Files {dirname} {
    set list [concat [Glob $dirname f "*"] [Glob $dirname f ".*"]]
    return [lsort -unique -ascii $list]
  }

  ##
  # Return list of all directories in $dirname
  #
  proc Dirs {dirname} {
    set list [concat [Glob $dirname d "*"] [Glob $dirname d ".*"]]
    return [lsort -unique -ascii $list]
  }
}

##
# ::Tree
#
# Functions to recursively read contents of directories
#
namespace eval Tree {
  ##
  # ::Tree::Src
  #
  # Functions to read contents of the source directory
  #
  namespace eval Src {
    ##
    # Recursively read contents of a directory specified by $rootnode, which
    # must be a name of an initialized "Node::Dir" object
    #
    proc Read {srcdir dirnode {root 1} {match 1}} {
      # Access node
      upvar $dirnode node

      # List of directories to store in $node
      set dirs [list]
      # List of files to store in $node
      set files [list]

      # Absolute directory name to glob
      if $root then {
       set globdir $srcdir
      } else {
       set globdir [file join $srcdir [Node::Dir::GetDirname node]]
      }

      # Process all directories in $node
      foreach dirname [Glob::Dirs $globdir] {
        # Full $dirname relative to $srcdir
        if $root then {
          set fulldirname $dirname
        } else {
          set fulldirname [file join [Node::Dir::GetDirname node] $dirname]
        }

        # A "Node::Dir" object representing $dirname
        set dir [Node::Dir::Init $fulldirname];

        # If $match != 1, then we're inside a directory with force copy flag
        if $match then {
          # Check if $dirname matches any ForceCopy(DirBasename)
          # or $fulldirname matches any ForceCopy(DirAbsolute)
          if "[Config::Fnmatch $dirname ForceCopy DirBasename]
              || [Config::Fnmatch $fulldirname ForceCopy DirAbsolute]" then {
            Node::Dir::SetForceCopy dir
          }

          # Check if $dirname matches any SrcIgnore(DirBasename)
          # or $fulldirname matches any SrcIgnore(DirAbsolute)
          if "[Config::Fnmatch $dirname SrcIgnore DirBasename]
              || [Config::Fnmatch $fulldirname SrcIgnore DirAbsolute]" then {
            Node::Dir::SetIgnore dir
          }

          # force copy flag overrides ignore flag
          if "[Node::Dir::GetForceCopy dir] && [Node::Dir::GetIgnore dir]" then {
            Msg::Note "$fulldirname: force copy flag overrides ignore flag"
            Node::Dir::SetIgnore dir 0
          }
        }

        # Recursively read contents of $dir
        if ![Node::Dir::GetIgnore dir] then {
          Read $srcdir dir 0 [expr ![Node::Dir::GetForceCopy dir]]
        }

        set dirs [lappend dirs $dir]
      }

      # Process all files in $node
      foreach filename [Glob::Files $globdir] {
        # Full $filename relative to $srcdir
        if $root then {
          set fullfilename $filename
        } else {
          set fullfilename [file join [Node::Dir::GetDirname node] $filename]
        }

        # A "Node::File" object representing $filename
        set file [Node::File::Init $filename]

        # If $match != 1, then we're inside a directory with force copy flag
        if $match {
          # Check if $filename matches any ForceCopy(FileBasename)
          # or $fullfilename matches any ForceCopy(FileAbsolute)
          if "[Config::Fnmatch $filename ForceCopy FileBasename]
              || [Config::Fnmatch $fullfilename ForceCopy FileAbsolute]" then {
            Node::File::SetForceCopy file
          }

          # Check if $filename matches any SrcIgnore(FileBasename)
          # or $fullfilename matches any SrcIgnore(FileAbsolute)
          if "[Config::Fnmatch $filename SrcIgnore FileBasename]
              || [Config::Fnmatch $fullfilename SrcIgnore FileAbsolute]" then {
            Node::File::SetIgnore file
          }

          # force copy flag overrides ignore flag
          if "[Node::File::GetForceCopy file] && [Node::File::GetIgnore file]" then {
            Msg::Note "$fullfilename: force copy flag overrides ignore flag"
            Node::File::SetIgnore file 0
          }
        }

        set files [lappend files $file]
      }

      Node::Dir::SetDirs node $dirs
      Node::Dir::SetFiles node $files
    }
  }

  ##
  # ::Tree::Dest
  #
  # Functions to read contents of a destination directory
  #
  namespace eval Dest {
    ##
    # Recursively read contents of a directory specified by $rootnode, which
    # must be a name of an initialized "Node::Dir" object
    #
    proc Read {destdir dirnode {root 1}} {
      # Access root node
      upvar $dirnode node

      # List of directories to store in $node
      set dirs [list]
      # List of files to store in $node
      set files [list]

      # Absolute directory name to glob
      if $root {
        set globdir $destdir
      } else {
        set globdir [file join $destdir [Node::Dir::GetDirname node]]
      }

      # Process all directories in $node
      foreach dirname [Glob::Dirs $globdir] {
        # Full $dirname relative to $destdir
        if $root then {
          set fulldirname $dirname
        } else {
          set fulldirname [file join [Node::Dir::GetDirname node] $dirname]
        }

        # Initialize "Node::Dir" object
        set dir [Node::Dir::Init $fulldirname];

        # Check if $dirname matches any DestIgnore(DirBasename)
        # or $fulldirname matches any DestIgnore(DirAbsolute)
        if "[Config::Fnmatch $dirname DestIgnore DirBasename]
            || [Config::Fnmatch $fulldirname DestIgnore DirAbsolute]" then {
          Node::Dir::SetIgnore dir
        }

        # Recursively read contents of $dir
        if ![Node::Dir::GetIgnore dir] then {
          Read $destdir dir 0
        }

        set dirs [lappend dirs $dir]
      }

      # Process all files in $node
      foreach filename [Glob::Files $globdir] {
        # Full $filename relative to $root
        if $root then {
          set fullfilename $filename
        } else {
          set fullfilename [file join [Node::Dir::GetDirname node] $filename]
        }

        # Initialize "Node::File" object
        set file [Node::File::Init $filename]

        # Check if $filename matches any DestIgnore(FileBasename)
        # or $fullfilename matches any DestIgnore(FileAbsolute)
        if "[Config::Fnmatch $filename DestIgnore FileBasename]
            || [Config::Fnmatch $fullfilename DestIgnore FileAbsolute]" then {
          Node::File::SetIgnore file
        }

        set files [lappend files $file]
      }

      Node::Dir::SetDirs node $dirs
      Node::Dir::SetFiles node $files
    }
  }

  ##
  # ::Tree::Diff
  #
  # This namespace defines function to recursively process directory nodes
  #
  namespace eval Diff {
    ##
    # Check if $name is in list $listvar
    #
    proc InList {name listvar} {
      # Access list
      upvar $listvar list

      return [expr [lsearch -exact $list $name] != -1]; # -nocase
    }

    ##
    # This function recursively processes directory nodes $srcnode and $destnode
    # which are root nodes for a source and a destination directory respectively
    #
    # It fills $outnode with list of files and directories to operate on
    #
    proc Process {srcnode destnode outnode} {
      # Access nodes
      upvar $srcnode src
      upvar $destnode dest
      upvar $outnode out

      # List of directories to store in $out
      set dirs [list]
      # List of files to store in $out
      set files [list]

      # Names of directories to ignore in $dest
      set IgnoredDirs [list]
      # Names of files to ignore in $dest
      set IgnoredFiles [list]

      # DirNodes()
      #
      # This array is set dynamicly
      #
      # Each member contains two "Node::Dir" objects: one from $src and
      # one from $dest
      #
      # This is required to recursively process those directories

      # Names of directories from $src to store in $out
      set DirNames [list]
      # Names of files from $src to store in $out
      set FileNames [list]

      # Process directories in $src
      foreach dir [Node::Dir::GetDirs src] {
        set dirname [Node::Dir::GetDirname dir]

        # If directory has force copy or ignore flag set,
        # add its name to IgnoredDirs
        if "[Node::Dir::GetForceCopy dir] || [Node::Dir::GetIgnore dir]" then {
          set IgnoredDirs [lappend IgnoredDirs $dirname]
        }

        # If $dir has ingore flag set, skip over it
        if [Node::Dir::GetIgnore dir] then {
          continue
        }

        # Create an empty "Node::Dir" object
        set node [Node::Dir::Init $dirname]

        set DirNodes($dirname) [list $dir $node]
      }

      # Get list of names currently in $DirNodes
      if [array exists DirNodes] then {
        set DirNames [array names DirNodes]
      }

      # Process directories in $dest
      foreach dir [Node::Dir::GetDirs dest] {
        set dirname [Node::Dir::GetDirname dir]

        # If $dir has ignore or force copy flag set in $src, skip over it
        if [InList $dirname IgnoredDirs] then {
          continue
        }

        # If $dir has ignore flag set, skip over it
        if [Node::Dir::GetIgnore dir] then {
          continue
        }

        # Add real node for $dir to DirNodes($dirname)
        if [InList $dirname DirNames] then {
          set DirNodes($dirname) [lreplace $DirNodes($dirname) 1 1 $dir]
          continue
        }

        # $dir does not exist in $src, use empty "Node::Dir" object
        set srcdir [Node::Dir::Init $dirname]

        set DirNodes($dirname) [list $srcdir $dir]
      }

      # Recursively process each directory in DirNodes()
      if [array exists DirNodes] then {
        foreach dirname [array names DirNodes] {
          foreach {srcdir destdir} $DirNodes($dirname) {
            # Initizalize "Node::Dir" object
            set dir [Node::Dir::Init $dirname]

            # Recursively process $srcdir and $destdir
            Process srcdir destdir dir

            # Apply force copy flag to $dir
            if [Node::Dir::GetForceCopy srcdir] then {
              Node::Dir::SetForceCopy dir
            }

            # Apply preserve flag to $dir
            if [Node::Dir::GetIgnore destdir] then {
              Node::Dir::SetPreserve dir
            }

            # Apply preserve flag to $out
            if [Node::Dir::GetPreserve dir] then {
              Node::Dir::SetPreserve out
            }

            set dirs [lappend dirs $dir]
          }
        }
      }

      # Process files in $src
      foreach file [Node::Dir::GetFiles src] {
        set filename [Node::File::GetFilename file]

        # $file has ignore flag set
        if [Node::File::GetIgnore file] then {
          set IgnoredFiles [lappend IgnoredFiles $filename]
          continue
        }

        # $file has force copy flag set
        if [Node::File::GetForceCopy file] then {
          set IgnoredFiles [lappend IgnoredFiles $filename]
        }

        set files [lappend files $file]
        set FileNames [lappend FileNames $filename]
      }

      # Process files in $dest
      foreach file [Node::Dir::GetFiles dest] {
        set filename [Node::File::GetFilename file]

        # $file is already in $files
        if [InList $filename FileNames] then {
          continue
        }

        # $file has ignore or force copy flag set in $src
        if [InList $filename IgnoredFiles] then {
          continue
        }

        # $file has ignore flag set in $dest
        if [Node::File::GetIgnore file] then {
          Node::Dir::SetPreserve out
          continue
        }

        set files [lappend files $file]
      }

      Node::Dir::SetDirs out $dirs
      Node::Dir::SetFiles out $files
    }
  }
}

##
# ::Fs
#
# Functions to interact with file system.
#
namespace eval Fs {
  ##
  # ::Fs::Stat
  #
  # Functions to access and set file attributes.
  #
  ##
  # Pseudo type "Fs::Stat"
  #
  # Fileds:
  #
  # Mtime
  # Atime
  #
  # [Unix]
  #
  # Permissions
  # Owner
  # Group
  #
  # [Windows]
  #
  # Hidden
  # Readonly
  #
  namespace eval Stat {
    # Avaialbe on all platforms
    set Attribute(Mtime) 0
    set Attribute(Atime) 1
    # Available on unix
    set Attribute(Permissions) 2
    set Attribute(Owner) 3
    set Attribute(Group) 4
    # Available on darwin and windows
    set Attribute(Readonly) 5
    set Attribute(Hidden) 6

    # TODO: handle darwin

    ##
    # Return "Fs::Stat" object containing attributes of $filename
    #
    proc Get {filename} {
      # Access global variables
      global tcl_platform
      # Access namespace variables
      variable Attribute

      # Initialize attribute list
      set a [list]

      # Modification time
      set a [linsert $a $Attribute(Mtime) [file mtime $filename]]
      # Access time
      set a [linsert $a $Attribute(Atime) [file atime $filename]]

      if [string equal $tcl_platform(platform) unix] then {
        # Owner
        set a [linsert $a $Attribute(Owner) [file attributes $filename -owner]]
        # Group
        set a [linsert $a $Attribute(Group) [file attributes $filename -group]]
        # Permissions
        set a [linsert $a $Attribute(Permissions) [file attributes $filename -permissions]]
      } else {
        # Dummy values
        set a [linsert $a $Attribute(Owner) -1]
        set a [linsert $a $Attribute(Group) -1]
        set a [linsert $a $Attribute(Permissions) -1]
      }

      if [string equal $tcl_platform(platform) windows] then {
        # Hidden attribute
        set a [linsert $a $Attribute(Hidden) [file attributes $filename -hidden]]
        # Readonly attribute
        set a [linsert $a $Attribute(Readonly) [file attributes $filename -readonly]]
      } else {
        # Dummy values
        set a [linsert $a $Attribute(Hidden) -1]
        set a [linsert $a $Attribute(Readonly) -1]
      }

      return $a
    }

    ##
    # Set $filename's attributes
    #
    proc Set {filename attributes} {
      # Access global variables
      global tcl_platform
      # Access namespace variables
      variable Attribute
      # Access attribute list
      upvar $attributes list

      if [Options::Get debug] {
        Msg::Note "setting attributes for $filename ([lindex $list])" stderr
      }

      if [Options::Get dry] then {
        return -code ok
      }

      file mtime $filename [lindex $list $Attribute(Mtime)]
      file atime $filename [lindex $list $Attribute(Atime)]

      if [string equal $tcl_platform(platform) unix] then {
        file attributes $filename -owner [lindex $list $Attribute(Owner)]
        file attributes $filename -group [lindex $list $Attribute(Group)]
        file attributes $filename -permissions [lindex $list $Attribute(Permissions)]
      }

      if [string equal $tcl_platform(platform) windows] then {
        file attributes $filename -hidden [lindex $list $Attribute(Hidden)]
        file attributes $filename -readonly [lindex $list $Attribute(Readonly)]
      }

      return -code ok
    }

    ##
    # Check if mtime specified in $attr1 is more recent than in $attr2
    #
    proc IsNewer {attr1 attr2} {
      # Access namespace variables
      variable Attribute
      # Access attribute lists
      upvar $attr1 list1
      upvar $attr2 list2

      set mtime1 [lindex $list1 $Attribute(Mtime)]
      set mtime2 [lindex $list2 $Attribute(Mtime)]

      return [expr $mtime1 > $mtime2]
    }
  }

  ##
  # ::Fs::Backup
  #
  # Functions to manage backups for files and directories.
  #
  ##
  # Pseudo type "Fs::Backup"
  #
  # Fields:
  #
  # OriginalName
  #   original filename
  #
  # BackupName
  #   backup filename
  #
  # Attributes
  #   "Fs::Stat" object containing attributes of original file
  #
  # IsDirectory
  #   `1` if backup is for directory, and `0` otherwise
  #
  namespace eval Backup {
    set Field(OriginalName) 0
    set Field(BackupName) 1
    set Field(Attributes) 2
    set Field(IsDirectory) 3

    ##
    # Get OriginalName field from "Fs::Backup" object $backup
    #
    proc GetOriginalName {backup} {
      # Access namespace variables
      variable Field
      # Access "Fs::Backup" object
      upvar $backup b

      return [lindex $b $Field(OriginalName)]
    }

    ##
    # Get BackupName field from "Fs::Backup" object $backup
    #
    proc GetBackupName {backup} {
      # Access namespace variables
      variable Field
      # Access "Fs::Backup" object
      upvar $backup b

      return [lindex $b $Field(BackupName)]
    }

    ##
    # Get Attributes field from "Fs::Backup" object $backup
    #
    proc GetAttributes {backup} {
      # Access namespace variables
      variable Field
      # Access "Fs::Backup" object
      upvar $backup b

      return [lindex $b $Field(Attributes)]
    }

    ##
    # Get IsDirectory field from "Fs::Backup" object $backup
    #
    proc GetIsDirectory {backup} {
      # Access namespace variables
      variable Field
      # Access "Fs::Backup" object
      upvar $backup b

      return [lindex $b $Field(IsDirectory)]
    }

    ##
    # Backup file or directory $filename and return "Fs::Backup" object
    # contining backup information
    #
    proc Backup {filename} {
      set backup [list]

      if [file exists $filename] then {
        if [Options::Get verbose] {
          Msg::Note "creating backup for $filename"
        }

        set backup [list $filename]

        # List of attempted backup names
        set names [list ${filename}~ ${filename}.bak ${filename}.old]

        foreach name $names {
          if ![file exists $name] {
            set backup [lappend backup $name]
            break
          }
        }

        if "[llength $backup] == 1" then {
          Msg::Fatal "failed to create backup filename for $filename"
        }

        set attributes [Fs::Stat::Get $filename]

        # Set Attributes field of $backup
        set backup [lappend backup $attributes]

        # Set IsDirectory field of $backup
        set backup [lappend backup [file isdirectory $filename]]

        if ![Options::Get dry] then {
          try {
            file rename -- [GetOriginalName backup] [GetBackupName backup]
          } on error {msg} {
            Msg::Fatal $msg
          }
        }
      }

      return $backup
    }

    ##
    # Restore file or directory from "Fs::Backup" object $backup
    #
    proc Restore {backup} {
      # Access backup
      upvar $backup b

      if "[llength $b]" then {
        if [Options::Get verbose] {
          Msg::Note "restoring from backup [GetOriginalName b]"
        }

        if [file exists [GetOriginalName b]] then {
          if [GetIsDirectory b] {
            Fs::Dir::RemoveDirectory [GetOriginalName b] 1
          } else {
            Fs::File::Remove [GetOriginalName b]
          }
        }

        if ![Options::Get dry] then {
          try {
            file rename -- [GetBackupName b] [GetOriginalName b]
          } on error {msg} {
            Msg::Fatal $msg
          }
        }
      }

      return -code ok
    }

    ##
    # Remove backup described in "Fs::Backup" object $backup
    #
    proc Remove {backup} {
      upvar $backup b

      if [llength $b] then {
        if [Options::Get verbose] {
          Msg::Note "removing backup [GetBackupName b]"
        }

        if [Fs::Backup::GetIsDirectory b] then {
          Fs::Dir::RemoveDirectory [GetBackupName b] 1
        } else {
          Fs::File::Remove [GetBackupName b]
        }
      }

      return -code ok
    }
  }

  ##
  # ::Fs::File
  #
  # Functions to manipulate files
  #
  namespace eval File {
    ##
    # Remove file $filename
    #
    proc Remove {filename} {
      if [Options::Get verbose] {
        Msg::Note "removing file $filename"
      }

      if ![Options::Get dry] then {
        try {
          file delete -force -- $filename
        } on error {msg} {
          Msg::Fatal $msg
        }
      }

      return -code ok
    }

    ##
    # Copy file $source to $target
    #
    # File is copied only if either:
    #
    # 1. force argument is supplied and is non-zero
    # 2. $target does not exist
    # 3. $source is newer than $target
    #
    proc Copy {source target {force 0}} {
      # Set to 1 if we really need to copy
      set copy $force

      # $target does not exist
      if ![file exists $target] then {
        set copy 1
      }

      # Get attributes from $source
      set Attributes(Source) [Fs::Stat::Get $source]

      if !$copy then {
        # Get attributes from $target
        set Attributes(Target) [Fs::Stat::Get $target]

        if "[Fs::Stat::IsNewer Attributes(Source) Attributes(Target)]" then {
          set copy 1
        }
      }

      if $copy then {
        # Get backup info for $target
        set backup [Fs::Backup::Backup $target]

        if [Options::Get verbose] {
          Msg::Note "copying file $source"
        }

        try {
          if ![Options::Get dry] then {
            file copy -- $source $target
          }
          Fs::Stat::Set $target Attributes(Source)
        } on error {msg} {
          Fs::Backup::Restore backup
          Msg::Fatal $msg
        } finally {
          Fs::Backup::Remove backup
        }
      }

      return -code ok
    }
  }

  ##
  # ::Fs::Dir
  #
  namespace eval Dir {
    ##
    # Remove directory $dirname
    # If force is non-zero, then $dirname may be non-empty
    #
    proc RemoveDirectory {dirname {force 0}} {
      if [Options::Get verbose] {
        Msg::Note "removing directory $dirname"
      }

      if ![Options::Get dry] then {
        try {
          if $force then {
            file delete -force -- $dirname
          } else {
            file delete -- $dirname
          }
        } on error {msg} {
          Msg::Fatal $msg
        }
      }

      return -code ok
    }

    ##
    # Recursively remove directory $node from $prefix
    #
    proc Remove {prefix node} {
      # Access node
      upvar $node dir

      # Absolute name of $dir
      set dirname [file join $prefix [Node::Dir::GetDirname dir]]

      foreach subdir [Node::Dir::GetDirs dir] {
        Remove $prefix subdir
      }

      foreach file [Node::Dir::GetFiles dir] {
        set filename [file join $dirname [Node::File::GetFilename file]]
        Fs::File::Remove $filename
      }

      RemoveDirectory $dirname
    }

    ##
    # Recursively copy directory $node from $src to $dest
    #
    proc Copy {src dest node} {
      # Access node
      upvar $node dir

      # Absolute name of $node in $src
      set srcdir [file join $src [Node::Dir::GetDirname dir]]
      # Absolute name of $node in $dest
      set destdir [file join $dest [Node::Dir::GetDirname dir]]

      # Get backup info for $destdir
      set backup [Fs::Backup::Backup $destdir]

      # Get attributes from $srcdir
      set attributes [Fs::Stat::Get $srcdir]

      if [Options::Get verbose] {
        Msg::Note "creating directory $destdir"
      }

      if ![Options::Get verbose] {
        try {
          file mkdir $destdir
        } on error {msg} {
          Fs::Backup::Restore backup
          Msg::Fatal $msg
        }
      }

      foreach subdir [Node::Dir::GetDirs dir] {
        Copy $src $dest subdir
      }

      foreach file [Node::Dir::GetFiles dir] {
        set filename [Node::File::GetFilename file]

        set srcfile [file join $srcdir $filename]
        set destfile [file join $destdir $filename]

        Fs::File::Copy $srcfile $destfile
      }

      # Set $srcdir's attributes to $destdir
      try {
        Fs::Stat::Set $destdir attributes
      } on error {msg} {
        Fs::Backup::Restore backup
        Msg::Fatal $msg
      } finally {
        Fs::Backup::Remove backup
      }

      return -code ok
    }
  }
}

##
# ::Dirsync
#
# This namespace defines functions to sync contents of directories
#
namespace eval Dirsync {
  ##
  # Recursively sync contents of $destnode with $srcnode
  # $dirnode must be the root node of $destnode
  #
  proc Sync {srcnode destnode dirnode {topdir 1}} {
    # Access nodes
    upvar $srcnode src
    upvar $destnode dest
    upvar $dirnode dir

    # Name of $src
    set srcdir [Node::Dir::GetDirname src]
    # Name of $dest
    set destdir [Node::Dir::GetDirname dest]

    # Process all files in $dir
    foreach file [Node::Dir::GetFiles dir] {
      set filename [Node::File::GetFilename file]

      if $topdir then {
        set srcfilename [file join $srcdir $filename]
        set destfilename [file join $destdir $filename]
      } else {
        set srcfilename [file join $srcdir [Node::Dir::GetDirname dir] $filename]
        set destfilename [file join $destdir [Node::Dir::GetDirname dir] $filename]
      }

      # File is missing
      if ![file exists $destfilename] then {
        Fs::File::Copy $srcfilename $destfilename
        continue
      }

      # File exists only in the destination directory
      if ![file exists $srcfilename] then {
        if ![Node::File::GetIgnore file] then {
          Fs::File::Remove $destfilename
        }
        continue
      }

      Fs::File::Copy $srcfilename $destfilename [Node::File::GetForceCopy file]
    }

    # Process all directories in $dir
    foreach subdir [Node::Dir::GetDirs dir] {
      set dirname [Node::Dir::GetDirname subdir]

      set srcdirname [file join $srcdir $dirname]
      set destdirname [file join $destdir $dirname]

      # $dirname does not exist in $dest
      # recursively copy $subdir from $src
      if ![file exists $destdirname] then {
        Fs::Dir::Copy $srcdir $destdir subdir
        continue
      }

      # $dirname exists in $dest, but not in $src
      # remove $subdir from $dest unless it has preserve flag set
      if ![file exists $srcdirname] then {
        if ![Node::Dir::GetPreserve subdir] then {
          Fs::Dir::Remove $destdir subdir
          continue
        }
      }

      # $dirname has force copy flag set
      if [Node::Dir::GetForceCopy subdir] {
        Fs::Dir::Copy $srcdir $destdir subdir
        continue
      }

      Sync src dest subdir 0
    }

    return -code ok
  }
}

##
# Parse options
#

Options::Set

##
# Read configs
#

Config::Init
Config::Destdir

Config::Read ForceCopy
Config::Read SrcIgnore
Config::Read DestIgnore

##
# Read $srcdir
#

# Initialize "Node::Dir" object
set src [Node::Dir::Init $Config::Srcdir]

Tree::Src::Read $Config::Srcdir src

##
# Process each destination directory in $Config::Destdirs
#

foreach destdir $Config::Destdirs {
  set dest [Node::Dir::Init $destdir]
  set diff [Node::Dir::Init $destdir]

  # Read $destdir
  Tree::Dest::Read $destdir dest

  # Generate list of files and directories to manipulate on
  Tree::Diff::Process src dest diff

  Dirsync::Sync src dest diff
}

exit 0
