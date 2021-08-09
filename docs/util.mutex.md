## lacord.util.mutex

This module provides a simple mutex implementation for synchronizing cqueues coroutines.

### *mutex*

This type has methods for locking and releasing the mutex and for delaying unlocks in various ways.

#### *mutex* `new()`

Creates a new mutex.


#### *nothing* `mutex:lock(timeout)`

Locks the mutex.

- *number (seconds)* `timeout`
    An optional timeout to wait before automatically releasing the lock.


#### *nothing* `mutex:unlock()`

Unlocks the mutex.

#### *nothing* `mutex:unlock_at(deadline)`

Unlocks the mutex at the given time in the future. This deadline should be based on the cqueues `monotime` clock.

- *number (seconds)* `deadline`

#### *nothing* `mutex:unlock_after(time)`

Unlocks the mutex after the given amount of seconds have elapsed.

- *number (seconds)* `time`

#### *nothing* `mutex:defer_unlock()`

Unlocks the mutex at some point in the near future.

- *number (seconds)* `time`



