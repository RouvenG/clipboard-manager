#!/usr/bin/env swift
// Sends a command to a running Debug build of ClipShelf.
// Usage: swift Scripts/debug-command.swift show | hide | type:<text> | key:<keyCode>[,cmd][,shift][,char=x]
//        | snapshot:<png path> | state:<json path>
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: debug-command.swift <command> [<command> ...]\n".utf8))
    exit(1)
}

for command in CommandLine.arguments.dropFirst() {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("io.github.rouveng.clipshelf.debug"), object: command, userInfo: nil, deliverImmediately: true)
    Thread.sleep(forTimeInterval: 0.4)
}
