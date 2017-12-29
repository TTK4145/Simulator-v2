import  std.stdio,
        std.conv,
        std.variant,
        std.concurrency,
        std.algorithm,
        std.range,
        std.typecons,
        std.typetuple,
        std.datetime,
        std.traits,
        core.time,
        core.thread,
        core.sync.mutex;
    

void addEvent(T)(Tid receiver, SysTime time, T value){
    //writeln("  Adding event: ", Event(receiver, Variant(value), t, false, Duration.init));
    synchronized(events_lock){
        events ~= Event(receiver, Variant(value), time, false, Duration.init);
    }
    t.send(EventsModified());
}


void addEvent(T)(Tid receiver, Duration dt, T value, Flag!"periodic" periodic = No.periodic){
    //writeln("  Adding event: ", Event(receiver, Variant(value), Clock.currTime + dt, periodic, dt));
    synchronized(events_lock){
        events ~= Event(receiver, Variant(value), Clock.currTime + dt, periodic, dt);
    }
    t.send(EventsModified());
}

void deleteEvent(Tid receiver, TypeInfo type, Delete which){
    //writeln("  Deleting event: ", receiver, " ", type, " ", which);
    synchronized(events_lock){
        final switch(which) with(Delete){
        case all:
            events = events.remove!(a => a.receiver == receiver && a.value.type == type)();
            break;
        case first:
            auto idx = events.countUntil!(a => a.receiver == receiver && a.value.type == type);
            if(idx != -1){
                events = events.remove(idx);
            }
            break;
        case last:
            auto idx = events.length - 1 - events.retro.countUntil!(a => a.receiver == receiver && a.value.type == type);
            if(idx != -1){
                events = events.remove(idx);
            }
            break;
        }
    }
    t.send(EventsModified());
}

enum Delete {
    all,
    first,
    last
}




private:

shared static this(){
    events_lock = new Mutex;
    t = spawn(&proc);
}


struct Event {
    Tid         receiver;
    Variant     value;
    SysTime     triggerTime;
    bool        periodic;
    Duration    period;
}

struct EventsModified {}


__gshared Tid t;
__gshared Mutex events_lock;
__gshared Event[] events;



void proc(){
    Duration timeUntilNext = 1.hours;
    
    while(true){
        //writeln("Time until next: ", timeUntilNext);
        receiveTimeout( timeUntilNext,
            (EventsModified n){
            },
            (OwnerTerminated o){
            },
            (Variant v){
            }
        );
        timeUntilNext = 1.hours;
        synchronized(events_lock){
            events.sort!(q{a.triggerTime < b.triggerTime})();
            //events.map!(a => a.to!string ~ "\n").reduce!((a, b) => a ~ b).writeln;
            iter:
            foreach(idx, ref item; events){
                if(Clock.currTime >= item.triggerTime){
                    item.receiver.send(item.value);
                    if(item.periodic){
                        item.triggerTime += item.period;
                    } else {
                        events = events.remove(idx);
                        goto iter;
                    }
                }
            }
            auto now = Clock.currTime;
            timeUntilNext = events.length ? 
                max(events.map!(a => a.triggerTime - now).reduce!min, 0.seconds) : 
                1.hours;
        }
    }
}
















