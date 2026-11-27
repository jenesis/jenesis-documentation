# Suspended event loop keeps its thread alive (auto-scaling event loop group)

We run Netty 4.2 with an event loop group that uses the auto-scaling event executor chooser
(`AutoScalingEventExecutorChooserFactory`), so that idle event loops are suspended and their threads go away when
load drops.

Every now and then an event loop ends up in a strange state: `isSuspended()` returns `true` for it, and the chooser
counts it as suspended, but its thread is still alive. A thread dump shows that thread parked inside the transport's
I/O handler, waiting for I/O, and it stays there. Nothing has been registered on that loop and no task is pending.
The thread only goes away once something else happens to wake that loop up (a task submitted to it, a channel
registered, a shutdown of the group). Until then the group has one more thread than it believes it has, and with
several such loops the number of live event loop threads does not shrink the way the chooser reports.

We see it with the epoll transport on Linux, not reliably: most suspensions work, and it seems to depend on timing.
We could not get it to happen with a plain `NioIoHandler` in a quick test.

What we expect: once an event loop has accepted a request to suspend (`trySuspend()` returned `true` and
`isSuspended()` reports it), its thread finishes promptly, whatever the loop was doing at the moment the request
arrived, and without needing anything else to happen on that loop.

How to reproduce, roughly: create a `SingleThreadIoEventLoop` (or a `MultiThreadIoEventLoopGroup` with the
auto-scaling chooser) over an I/O handler that, like the epoll one, only reacts to a wake-up while it is actually
blocked, let the loop run a task so its thread starts, and call `trySuspend()` from another thread while the loop is
about to go back to waiting for I/O. Sometimes the call returns `true`, `isSuspended()` is `true`, and the loop's
thread is still alive long afterwards.
