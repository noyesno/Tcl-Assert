package provide tcl::assert 0.1

#//////////////////////////////////////////////////////////
#// Project: Tcl-Assert
#// By: noyesno.net@gmail.com
#// At: 2011
#//
#// Used for Testing Tcl Based Applications
#//////////////////////////////////////////////////////////

if 0 {
%% set logfile $some_log_file

%% capture {
report_timing
%% } cp_a

%% capture -start cp_a
report_timing
%% capture -end

%% assert expr [llength $list]==3
%% assert expr [llength $list]==3
%% assert diff {i:/file/golden.txt} {r:/file/output.txt}
%% filter grep Error    ; # line grep
%% filter lgrep Error   ; # list grep
%% filter regexp {\d+}  ; # list grep
%% save cp_2
%% save {i:/cp_2.log}
%% use cp_2
}


###############################################################
# Helper for the Safe-Interpreter
###############################################################

namespace eval faint {
  proc log {level args} {
    switch $level {
      "info"    { puts "#%%# Info: [join $args]" }
      "warn"    { puts "#%%# Warn: [join $args]" }
      "debug"   { puts "#%%# DEBUG: [join $args]" }
      "assert"  { puts "#%%# ASSERT: [join $args]" }
      "fail"    { puts "#%%# ASSERT-FAIL: [join $args]" }
      "pass"    { puts "#%%# ASSERT-PASS: [join $args]" }
      default   { puts "#%%# $level: [join $args]" }
   }
  }

  proc __set {name args} {
    if {[llength $args]>0} {
      return -code error "The variable is readonly"
    }
    return [uplevel array $op $args]
  }

  proc __array {op args} {
    switch $op {
      "size"   -
      "names"  -
      "exists" -
      "get"    {
        return [uplevel array $op $args]
      }
      default  {
        return -code error "The array is readonly"
      }
    }
  }

  proc __load {modle} {
  }


  proc __source {args} {
    set file [lindex $args end]
    log debug "source $file"
    _%%_ invokehidden source $file
  }

  proc __exec {args} {
    log debug "exec [lindex $args 0]"
    eval _%%_ invokehidden exec $args
  }
}


###############################################################
# Init Safe-Interpreter
###############################################################
if [interp exists _%%_] {interp delete _%%_}
interp create -safe _%%_
interp alias {} %% _%%_ __eval
interp alias _%%_ redirect {} redirect
interp alias _%%_ __set   {} faint::__set
interp alias _%%_ __array {} faint::__array
interp alias _%%_ log     {} faint::log
interp alias _%%_ source  {} faint::__source
interp alias _%%_ exec    {} faint::__exec

interp eval _%%_ {

proc __eval {args} {
    uplevel $args
}



proc reset {} {
  set ::scenario  ""
  set ::capture   ""
  set ::logfile   ""
  set ::n_assert  0
  set ::n_pass    0
  set ::n_fail    0
  set ::n_capture 0    ; # Number of capture
  set ::n_marks   0    ; # Number of mark
  array unset ::buffer
}

reset

proc unknown {args} {
  log debug "unknow $args"
}

proc scenario {text} {
  set ::scenario $text
  log "Scenario" "$::scenario"
  mark -start SCN:%n
}



#========================================================
# TODO: use return value 0 as PASS
# TODO: may need a catch for eval below
# %% assert grep Error
# %% assert -false  grep Error
# %% assert ! grep Error
# %% assert grep Error
#========================================================
proc assert {args} {

  if {[llength $args] == 0} {
    set status [expr $::n_fail==0?"PASS":"FAIL"]
    log assert "$status @ $::n_pass PASS + $::n_fail FAIL = $::n_assert ASSERT"
    return
  }

  set -v 0
  if {[lindex $args 0] == "!"} {
    set -v 1
    set command [lrange $args 1 end]
  } else {
    set command $args
  }

  set pos [lsearch -exact $command "%%"]
  if {$pos > 0} {
    set text [__read]
    lset command $pos $text
  }
  set rv [uplevel $command]

  if ${-v} {
    set rv [expr {!$rv}]
  }

  incr ::n_assert
  if {$rv} {
    incr ::n_pass
    log pass "$::n_pass/$::n_assert"
  } else {
    incr ::n_fail
    log fail "$::n_fail/$::n_assert"
  }
  return
}

proc filter {args} {
  set command $args

  set pos [lsearch -exact $command "%%"]
  if {$pos > 0} {
    set text [__read]
    lset command $pos $text
  }
  set ::buffer() [uplevel $command]
  return
}

proc assert_expr {args} {
  return [uplevel expr $args]
}

#===============================================
# %% assert match  "Library*"
# %% assert regexp "^Library"
#
# %% assert grep   "^Library"
#===============================================

proc assert_match {pattern {text ""}} {
  set text [__read $text]
  return [string match $pattern $text]
}

proc assert_regexp {pattern {text ""}} {
  set text [__read $text]
  return [regexp $pattern $text]
}

proc assert_grep {pattern {text ""}} {
  set text [__read $text]
  return [regexp -line $pattern $text]
}

#===============================================
# %% assert diff a b
#===============================================
proc assert_diff {{filea ""} {fileb ""}} {
}

#===============================================
# %% assert array diff a b
#===============================================
proc assert_array {op aa ab} {
  if {$op=="diff"} {
    return [eval  assert_array@diff $aa $ab]
  }
  return 0
}

proc assert_array@diff {aa ab} {
  set size_b [__array size $ab]
  foreach {k v} [__array get $aa *] {
    set pairs [__array get $ab $k]
    if {[llength $pairs]==0} {
      log info "< key $k not exist in array $ab"
      return 0
    } elseif {[lindex $pairs 1] != $v} {
      log info "! values for key $k not the same: $v != [lindex $pairs 1]"
      return 0
    } else {
      incr size_b -1
    }
  }
  if {$size_b>0}  {
    log info "> array $ab has $size_b more elements than $aa"
    return 0
  }
  return 1
}



#===============================================
# %% filter grep "^Error"
# %% filter grep -v "^Error"
#===============================================
proc filter_grep {args} {
  set -v 0
  if {[lindex $args 0] == "-v"} {
    foreach {-v pattern text} $args break
    set -v 1
  } else {
    foreach {pattern text} $args break
  }

  set text [__read $text]
  set lines [list]
  foreach line [split $text "\n"] {
    if {[regexp $pattern $line] != ${-v}} {
      lappend lines $line
    }
  }

  set ::buffer() [join $lines "\n"]
  return
}

#===============================================
# %% filter lgrep "^\d+\.\d+$"
#===============================================
proc filter_lgrep {pattern {text ""}} {
  set text [__read $text]

  set toks [list]
  foreach tok $text {
    if [regexp $pattern $tok] { lappend toks $tok}
  }

  set ::buffer() $toks
  return
}

#===============================================
# %% use CP1
#===============================================

proc use {name} {
  if [info exists ::buffer()] {
    unset ::buffer()
  }

  set ::mark $name
  return
}

#===============================================
# %% save i:/dump.txt
#===============================================
proc save {{name ""}} {
  switch -glob $name {
    {i:/*} {
      set name [string range $name 3 end]
      # TODO: write to file
    }
    "?*" {
      set ::buffer($name) $::buffer()
    }
    default {
      # do nothing
      # write to a file???
    }
  }
  return
}

proc capture {cmds {name ""}} {
  redirect -variable %% $cmds
  set ::buffer($name) [__set %%]
}

proc mark {op {name ""}} {
  if [info exists ::buffer()] {
    unset ::buffer()
  }
  switch -- $op {
    -stop  -
    -end   {
      if {$name == ""} { set name $::mark }
      log ">>>" $name
    }
    -begin -
    -start {
      incr ::n_marks
      if {$name == ""} { set name "CP:$::n_marks" }
      set name [regsub {%n} $name $::n_marks]
      set ::mark $name
      log "<<<" $name
    }
    default {
      set name $op
      incr ::n_marks
      if {$name == ""} { set name "CP:$::n_marks" }
      set name [regsub {%n} $name $::n_marks]
      set ::mark $name
      log "<<<" $name
    }
  }
}

#===============================================
# __read i:/dump.txt
# __read r:/dump.txt
# __read i:CP1
# __read CP1
# __read
#===============================================
proc __read {{name ""}} {
  switch -glob $name {
    {[ir]:/*} {
      set box  [string index $name 0]
      set name [string range $name 3 end]
    }
    {[i]:*} {
      set box  [string index $name 0]
      set name [string range $name 2 end]
      return $::buffer($name)
    }
    "?*" {
      return $::buffer($name)
    }
    default {
      if ![info exists ::buffer()] {
	set text [exec sed [subst {/^#%%# <<<: $::mark/,/^#%%# >>>: $::mark/ ! d ; /^#%%#/ d ; /^%%/ d}] $::logfile]
	set ::buffer() $text
      }
      return $::buffer()
    }
  }
}

} ; # end interp eval
