//
//  main.swift
//  IOSurfaceBroker
//
//  Created by Vyacheslav Gilevich on 16.07.2025.
//

import Foundation
import XPC           // low‑level C API
import IOSurface
import os.lock       // for os_unfair_lock

// MARK: – single-slot cache

let serviceName = "com.aiqa.IOSurfaceBroker"

var lastSurf: xpc_object_t?

func peer_event_handler(peer: xpc_connection_t, event: xpc_object_t) {
    let type = xpc_get_type(event)
    
    if type == XPC_TYPE_ERROR {
        if event === XPC_ERROR_CONNECTION_INVALID {
            print("IOSurfaceBroker: Client disconnected")
        } else if event === XPC_ERROR_TERMINATION_IMMINENT {
            print("IOSurfaceBroker: Service termination imminent")
        } else {
            print("IOSurfaceBroker: Unknown error")
        }
    } else if type == XPC_TYPE_DICTIONARY {
        // Handle the message
        let reply = xpc_dictionary_create_reply(event)
        
        if let command = xpc_dictionary_get_string(event, "cmd") {
            let commandString = String(cString: command)
            
            if commandString == "sendSurface" {
                lastSurf = xpc_dictionary_get_value(event, "surf")
                if let reply = reply {
                    xpc_dictionary_set_string(reply, "status", "ok")
                    xpc_connection_send_message(peer, reply)
                }
            } else if commandString == "acquire" {
                if let reply = reply {
                    if let surf = lastSurf {
                        xpc_dictionary_set_value(reply, "surf", surf)
                    }
                    xpc_connection_send_message(peer, reply)
                }
            } else {
                if let reply = reply {
                    xpc_dictionary_set_string(reply, "status", "incorrect command")
                    xpc_connection_send_message(peer, reply)
                }
            }
        }
    }
}

func connection_handler(connection: xpc_connection_t) {
    xpc_connection_set_event_handler(connection, { event in
        peer_event_handler(peer: connection, event: event)
    })
    
    xpc_connection_resume(connection)
}

// MARK: - LaunchAgent main

print("IOSurfaceBroker: Starting service...")

// Create XPC listener for the service
let listener = xpc_connection_create_mach_service(
    serviceName,
    DispatchQueue.main,
    UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER)
)

xpc_connection_set_event_handler(listener) { event in
    let type = xpc_get_type(event)
    
    if type == XPC_TYPE_CONNECTION {
        print("IOSurfaceBroker: New client connection")
        let connection = event as! xpc_connection_t
        connection_handler(connection: connection)
    } else if type == XPC_TYPE_ERROR {
        if event === XPC_ERROR_TERMINATION_IMMINENT {
            print("IOSurfaceBroker: Service termination imminent")
        } else {
            print("IOSurfaceBroker: Unknown error in listener")
        }
    }
}

xpc_connection_resume(listener)
print("IOSurfaceBroker: Service started, waiting for connections...")

// Run the main run loop to keep the service alive
RunLoop.main.run()
