#!/usr/bin/expect
set ip [lindex $argv 0]
set user [lindex $argv 1]
set pwd [lindex $argv 2]
set rpwd [lindex $argv 3]
spawn ssh $user@$ip -oStrictHostKeyChecking=no
expect "*password:"
send "${pwd}\r"
expect "*#"
send "su -\r"
expect "Password:" { send "${rpwd}\r" }
interact
