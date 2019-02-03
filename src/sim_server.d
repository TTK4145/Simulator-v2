import  std.algorithm,
        std.concurrency,
        std.conv,
        std.datetime,
        std.file,
        std.getopt,
        std.math,
        std.process,
        std.random,
        std.range,
        std.socket,
        std.stdio,
        std.uni,
        core.exception;

import timer_event;



///----------------------///
/// -----  CONFIG  ----- ///
///----------------------///

struct SimConfig {
    ushort      port                    = 15657;
    
    int         numFloors               = 4;
    
    Duration    travelTimeBetweenFloors = 2.seconds;
    Duration    travelTimePassingFloor  = 500.msecs;
    Duration    btnDepressedTime        = 200.msecs;
    bool        stopMotorOnDisconnect   = true;

    char        light_off               = '-';
    char        light_on                = '*';    

    char        key_stopButton          = 'p';
    char        key_obstruction         = '-';
    char        key_moveUp              = '9';
    char        key_moveStop            = '8';
    char        key_moveDown            = '7';
    char        key_moveInbounds        = '0';
    string[]    key_orderButtons       = [
                                            "qwertyui?",
                                            "?sdfghjkl",
                                            "zxcvbnm,.",
                                        ];
}


__gshared SimConfig cfg;


SimConfig parseConfig(string[] contents, SimConfig old = SimConfig.init){
    int travelTimeBetweenFloors_ms;
    int travelTimePassingFloor_ms;
    int btnDepressedTime_ms;
    string stopMotorOnDisconnect_str;
    string key_ordersUp;
    string key_ordersDown;
    string key_ordersCab;
    
    SimConfig cfg = old;

    getopt( contents,
        std.getopt.config.passThrough,
        "port",                         &cfg.port,
        "numFloors",                    &cfg.numFloors,
        "travelTimeBetweenFloors_ms",   &travelTimeBetweenFloors_ms,
        "travelTimePassingFloor_ms",    &travelTimePassingFloor_ms,
        "btnDepressedTime_ms",          &btnDepressedTime_ms,
        "stopMotorOnDisconnect",        &stopMotorOnDisconnect_str,
        "light_off",                    &cfg.light_off,
        "light_on",                     &cfg.light_on,
        "key_ordersUp",                 &key_ordersUp,
        "key_ordersDown",               &key_ordersDown,
        "key_ordersCab",                &key_ordersCab,
        "key_stopButton",               &cfg.key_stopButton,
        "key_obstruction",              &cfg.key_obstruction,
        "key_moveUp",                   &cfg.key_moveUp,
        "key_moveStop",                 &cfg.key_moveStop,
        "key_moveDown",                 &cfg.key_moveDown,
        "key_moveInbounds",             &cfg.key_moveInbounds,
    );

    if(travelTimeBetweenFloors_ms   != 0){  cfg.travelTimeBetweenFloors = travelTimeBetweenFloors_ms.msecs; }
    if(travelTimePassingFloor_ms    != 0){  cfg.travelTimePassingFloor  = travelTimePassingFloor_ms.msecs;  }
    if(btnDepressedTime_ms          != 0){  cfg.btnDepressedTime        = btnDepressedTime_ms.msecs;        }
    if(stopMotorOnDisconnect_str    != ""){ cfg.stopMotorOnDisconnect   = stopMotorOnDisconnect_str.to!bool;}
    if(key_ordersUp                 != ""){ cfg.key_orderButtons[0]     = key_ordersUp ~ "?";               }
    if(key_ordersDown               != ""){ cfg.key_orderButtons[1]     = "?" ~ key_ordersDown;             }
    if(key_ordersCab                != ""){ cfg.key_orderButtons[2]     = key_ordersCab;                    }
    
    return cfg;
}

SimConfig loadConfig(string[] cmdLineArgs, string configFileName, SimConfig old = SimConfig.init){
    try {
        old = configFileName.readText.split.parseConfig(old);
    } catch(Exception e){
        writeln("Encountered a problem when loading ", configFileName, ": ", e.msg, "\nUsing default settings...");
        
    }
    
    if(cmdLineArgs.length > 1){
        writeln("Parsing command line args...");
        old = cmdLineArgs.parseConfig(old);
    }
    return old;
}





///-----------------------------///
/// -----  MESSAGE TYPES  ----- ///
///-----------------------------///


/// --- PANEL --- ///

struct StdinChar {
    char c;
    alias c this;
}

enum BtnAction {
    Press,
    Release,
    Toggle
}

struct OrderButton {
    int floor;
    int btnType;
    BtnAction action;
}

struct StopButton {
    BtnAction action;
    alias action this;
}

struct ObstructionSwitch {}


/// --- INTERFACE --- ///

// -- Write -- //

struct MotorDirection {
    Dirn dirn;
    alias dirn this;
}

struct OrderButtonLight {
    int floor;
    BtnType btnType;
    bool value;
}

struct FloorIndicator {
    int floor;
    alias floor this;
}

struct DoorLight {
    bool value;
    alias value this;
}

struct StopButtonLight {
    bool value;
    alias value this;
}

struct ReloadConfig {}

// -- Read -- //

struct OrderButtonRequest {
    int floor;
    BtnType btnType;
}

struct FloorSensorRequest {}

struct StopButtonRequest {}

struct ObstructionRequest {}


/// --- MOVEMENT --- ///

struct FloorArrival {
    int floor;
    alias floor this;
}

struct FloorDeparture {
    int floor;
    alias floor this;
}

struct ManualMoveWithinBounds {}

/// --- LOG --- ///

struct ClientConnected {
    bool value;
    alias value this;
}



///---------------------///
/// -----  TYPES  ----- ///
///---------------------///

enum Dirn {
    Down    = -1,
    Stop    = 0,
    Up      = 1,
}

enum BtnType {
    Up      = 0,
    Down    = 1,
    Cab     = 2,
}

final class SimulationState {
    this(Flag!"randomStart" randomStart, int numFloors){
        assert(2 <= numFloors  &&  numFloors <= 9);
        this.numFloors  = numFloors;
        orderButtons    = new bool[3][](numFloors);
        orderLights     = new bool[3][](numFloors);
        
        bg = new char[][](8, 27 + 4*numFloors);

        if(randomStart){
            prevFloor = uniform(0, numFloors);
            currFloor = dice(50, 50) ? -1 : prevFloor;
            if(currFloor == -1  &&  prevFloor == 0){
                departDirn = Dirn.Up;
            } else if(currFloor == -1  &&  prevFloor == numFloors-1){
                departDirn = Dirn.Down;
            } else {
                departDirn = dice(50, 50) ? Dirn.Up : Dirn.Down;
            }
            currDirn = Dirn.Stop;
        } else {
            currDirn    = Dirn.Stop;
            currFloor   = 0;
            departDirn  = Dirn.Up;
            prevFloor   = 0;
        }
        resetBg;
    }

    this(Flag!"randomStart" randomStart){
        this(randomStart, 4);
    }

    immutable int numFloors;

    bool[3][]   orderButtons;
    bool[3][]   orderLights;
    bool        stopButton;
    bool        stopButtonLight;
    bool        obstruction;
    bool        doorLight;
    int         floorIndicator;

    Dirn        currDirn;
    int         currFloor;      // 0..numFloors, or -1 when between floors
    Dirn        departDirn;     // Only Dirn.Up or Dirn.Down
    int         prevFloor;      // 0..numFloors, never -1
    bool        isOutOfBounds(){ return (currFloor == -1  &&  departDirn == Dirn.Down  &&  prevFloor == 0) || 
                                        (currFloor == -1  &&  departDirn == Dirn.Up    &&  prevFloor == numFloors-1); }
    

    char[][]    bg;
    bool        clientConnected;
    int         printCount;

    invariant {
        assert(-1 <= currFloor  && currFloor < numFloors,
            "currFloor is not between -1..numFloors");
        assert(0 <= prevFloor  && prevFloor < numFloors,
            "prevFloor is not between 0..numFloors");
        assert(departDirn != Dirn.Stop,
            "departDirn is Dirn.Stop");
    }

    void resetState(){
        orderButtons    = new bool[3][](numFloors);
        orderLights     = new bool[3][](numFloors);
        stopButton      = false;
        stopButtonLight = false;
        obstruction     = false;
        doorLight       = false;
        floorIndicator  = 0;
    }

    void resetBg(){
        foreach(ref line; bg){
            foreach(ref c; line){
                c = ' ';
            }
        }
        bg[0][] = "+-----------+"   ~ "-".repeat(cfg.numFloors*4+1).join                    ~ "+            ";
        bg[1][] = "|           |"   ~ " ".repeat(cfg.numFloors*4+1).join                    ~ "|            ";
        bg[2][] = "| Floor     |  " ~ iota(0, cfg.numFloors).map!(to!string).join("   ")  ~ "  |            ";
        bg[3][] = "+-----------+"   ~ "-".repeat(cfg.numFloors*4+1).join                    ~ "+-----------+";
        bg[4][] = "| Hall Up   |"   ~ " ".repeat(cfg.numFloors*4+1).join                    ~ "| Door:     |";
        bg[5][] = "| Hall Down |"   ~ " ".repeat(cfg.numFloors*4+1).join                    ~ "| Stop:     |";
        bg[6][] = "| Cab       |"   ~ " ".repeat(cfg.numFloors*4+1).join                    ~ "| Obstr:    |";
        bg[7][] = "+-----------+"   ~ "-".repeat(cfg.numFloors*4+1).join                    ~ "+-----------+";
    }

    override string toString(){
        // Reset
        bg[1][13..14+numFloors*4] = " ".repeat(numFloors*4+1).join;
        foreach(f; 0..numFloors){
            bg[2][16+f*4] = ' ';
        }


        bg[2][16+floorIndicator*4]      = cfg.light_on;
        bg[4][$-3] = doorLight          ? cfg.light_on  : cfg.light_off;
        bg[5][$-3] = stopButtonLight    ? cfg.light_on  : cfg.light_off;
        bg[6][$-3] = obstruction        ? 'v' : '^';

        foreach(floor, lightsAtFloor; orderLights){
            foreach(btnType, lightEnabled; lightsAtFloor){
                if( (btnType == BtnType.Up  &&  floor == cfg.numFloors-1) ||
                    (btnType == BtnType.Down  &&  floor == 0)
                ){
                    continue;
                }
                bg[4+btnType][15+floor*4] = lightEnabled ? cfg.light_on : cfg.light_off;
            }
        }

        int elevatorPos;
        if(currFloor != -1){
            elevatorPos = 15+currFloor*4;
        } else {
            if(departDirn == Dirn.Up){
                elevatorPos = 17+prevFloor*4;
            }
            if(departDirn == Dirn.Down){
                elevatorPos = 13+prevFloor*4;
            }
        }
        bg[1][elevatorPos] = '#';
        if(currDirn == Dirn.Up){
            bg[1][elevatorPos+1] = '>';
        }
        if(currDirn == Dirn.Down){
            bg[1][elevatorPos-1] = '<';
        }

        auto cc = clientConnected ? 
            "Connected   " : 
            "Disconnected" ;
        bg[2][$-12..$-12+cc.length] = cc[0..$];
        
        auto pc = (++printCount).to!(char[]);
        bg[7][$-1-pc.length..$-1] = pc[0..$];

        return bg.map!(a => a.to!string).reduce!((a, b) => a ~ "\n" ~ b);
    }

}

struct ConsolePoint {
    int x;
    int y;
}

version(Windows){
    import core.sys.windows.wincon;
    import core.sys.windows.winbase;
    void setCursorPos(ConsolePoint p){
        COORD coord = {
            cast(short)min(100, max(0, p.x)),
            cast(short)max(0, p.y)
        };
        stdout.flush();
        SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), coord);
    }
    
    ConsolePoint cursorPos(){
        CONSOLE_SCREEN_BUFFER_INFO info;
        GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info);
        return ConsolePoint(info.dwCursorPosition.X, info.dwCursorPosition.Y);
    }
    
    void clearConsoleLine(){
        CONSOLE_SCREEN_BUFFER_INFO info;
        GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info);
        
        auto y = cursorPos().y;
        setCursorPos(ConsolePoint(0, y));
        writeln(' '.repeat(info.dwSize.X)); 
        setCursorPos(ConsolePoint(0, y));
    }
}

version(Posix){
    import core.sys.posix.termios;
        
    void setCursorPos(ConsolePoint p){
        stdout.flush();
        writef("\033[%d;%df", p.y, p.x);
    }
    
    ConsolePoint cursorPos(){
        char[] buf;

        write("\033[6n");
        stdout.flush();
        foreach(i; 0..8){
            char c;
            c = cast(char)getchar();
            buf ~= c;
            if(c == 'R'){
                break;
            }
        }

        buf = buf[2..$-1];
        auto tmp = buf.split(";");

        return ConsolePoint(to!int(tmp[1]) - 1, to!int(tmp[0]) - 1);
    }
    
    void clearConsoleLine(){
        writef("\033[K");
    }
}




void main(string[] args){
    try {

    cfg = loadConfig(args, "simulator.con");

    auto state = new SimulationState(Yes.randomStart, cfg.numFloors);
    writeln('\n'.repeat(state.bg.length.to!int+1));
    ConsolePoint cp = cursorPos;
    cp.y = max(0, cp.y-(state.bg.length.to!int+1));
    
    void printState(){
        setCursorPos(cp);
        state.writeln;
    }
    printState;
    

    auto stdinParseTid          = spawnLinked(&stdinParseProc, thisTid);
    auto stdinGetterTid         = spawnLinked(&stdinGetterProc, stdinParseTid);
    auto networkInterfaceTid    = spawnLinked(&networkInterfaceProc, thisTid);
    
    
    import core.thread : Thread;
    foreach(ref t; Thread.getAll){
        t.isDaemon = true;
    }    

    auto stateUpdated = false;

    while(true){
        if(stateUpdated){
            printState;
        }
        stateUpdated = true;
        
        receive(
            /// --- RESET --- ///

            (ReloadConfig r){
                cfg = loadConfig(args, "simulator.con", cfg);
                auto prevPrintCount = state.printCount;
                state = new SimulationState(Yes.randomStart, cfg.numFloors);
                state.printCount = prevPrintCount;
                state.clientConnected = true;
            },


            /// --- WRITE --- ///

            (MotorDirection md){
                assert(Dirn.min <= md &&  md <= Dirn.max,
                    "Tried to set motor direction to invalid direction " ~ md.to!int.to!string);
                if(state.currDirn != md  &&  !state.isOutOfBounds){
                    state.currDirn = md;

                    if(state.currFloor == -1){
                        deleteEvent(thisTid, typeid(FloorArrival), Delete.all);
                    } else {
                        deleteEvent(thisTid, typeid(FloorDeparture), Delete.all);
                    }

                    if(md != Dirn.Stop){
                        if(state.currFloor != -1){
                            // At a floor: depart this floor
                            addEvent(thisTid, cfg.travelTimePassingFloor, FloorDeparture(state.currFloor));
                            state.departDirn = md;
                        } else {
                            // Between floors
                            if(state.departDirn == md){
                                // Continue in that direction
                                addEvent(thisTid, cfg.travelTimeBetweenFloors, FloorArrival(state.prevFloor + md));
                            } else {
                                // Go back to previous floor
                                addEvent(thisTid, cfg.travelTimeBetweenFloors, FloorArrival(state.prevFloor));
                            }
                        }
                    }
                }
            },
            (OrderButtonLight obl){
                assert(0 <= obl.floor  &&  obl.floor < state.numFloors,
                    "Tried to set order button light at non-existent floor " ~ obl.floor.to!string);
                assert(0 <= obl.btnType  &&  obl.btnType <= BtnType.max,
                    "Tried to set order button light for invalid button type " ~ obl.btnType.to!int.to!string);
                state.orderLights[obl.floor][obl.btnType] = obl.value;
            },
            (FloorIndicator fi){
                assert(0 <= fi  &&  fi < state.numFloors,
                    "Tried to set floor indicator to non-existent floor " ~ fi.to!string);
                state.floorIndicator = fi;
            },
            (DoorLight dl){
                state.doorLight = dl;
            },
            (StopButtonLight sbl){
                state.stopButtonLight = sbl;
            },


            /// --- READ --- ///

            (Tid receiver, OrderButtonRequest req){
                stateUpdated = false;
                assert(0 <= req.floor  &&  req.floor < state.numFloors,
                    "Tried to read order button at non-existent floor " ~ req.floor.to!string);
                assert(0 <= req.btnType  &&  req.btnType <= BtnType.max,
                    "Tried to read order button for invalid button type " ~ req.btnType.to!int.to!string);
                if( (req.btnType == BtnType.Up && req.floor == state.numFloors-1) ||
                    (req.btnType == BtnType.Down && req.floor == 0)
                ){
                    receiver.send(false);
                } else {
                    receiver.send(state.orderButtons[req.floor][req.btnType]);
                }
            },
            (Tid receiver, FloorSensorRequest req){
                stateUpdated = false;
                receiver.send(state.currFloor);
            },
            (Tid receiver, StopButtonRequest req){
                stateUpdated = false;
                receiver.send(state.stopButton);
            },
            (Tid receiver, ObstructionRequest req){
                stateUpdated = false;
                receiver.send(state.obstruction);
            },




            /// --- PANEL INPUTS --- ///

            (OrderButton ob){
                if(ob.floor < state.numFloors){
                    final switch(ob.action) with(BtnAction){
                    case Press:
                        state.orderButtons[ob.floor][ob.btnType] = true;
                        break;
                    case Release:
                        state.orderButtons[ob.floor][ob.btnType] = false;
                        break;
                    case Toggle:
                        state.orderButtons[ob.floor][ob.btnType] = !state.orderButtons[ob.floor][ob.btnType];
                        break;
                    }
                }
            },
            (StopButton sb){
                final switch(sb.action) with(BtnAction){
                case Press:
                    state.stopButton = true;
                    break;
                case Release:
                    state.stopButton = false;
                    break;
                case Toggle:
                    state.stopButton = !state.stopButton;
                    break;
                }
            },
            (ObstructionSwitch os){
                state.obstruction = !state.obstruction;
            },


            /// --- MOVEMENT --- ///

            (FloorArrival f){
                assert(state.currDirn != Dirn.Stop,
                    "Elevator arrived at a floor with currDirn == Dirn.Stop");
                assert(0 <= f  &&  f <= state.numFloors,
                    "Elevator \"arrived\" at a non-existent floor\n");
                assert(
                    (state.currDirn == Dirn.Up   && f >= state.prevFloor) ||
                    (state.currDirn == Dirn.Down && f <= state.prevFloor),
                    "Elevator arrived at a floor in the opposite direction of travel\n");
                assert(abs(f - state.prevFloor) <= 1,
                    "Elevator skipped a floor");


                state.currFloor = f;
                state.prevFloor = f;
                addEvent(thisTid, cfg.travelTimePassingFloor, FloorDeparture(state.currFloor));
            },
            (FloorDeparture f){
                if(state.currDirn == Dirn.Down && f <= 0){
                    writeln("Elevator departed the bottom floor going downward! ",
                            "Press [", cfg.key_moveInbounds, "] to move the elevator within bounds...\n");
                } else if(state.currDirn == Dirn.Up && f >= state.numFloors-1){
                    writeln("Elevator departed the top floor going upward! ",
                            "Press [", cfg.key_moveInbounds, "] to move the elevator within bounds...\n");
                } else {
                    addEvent(thisTid, cfg.travelTimeBetweenFloors, FloorArrival(state.prevFloor + state.currDirn));
                }
                state.currFloor = -1;
                state.departDirn = state.currDirn;
            },
            (ManualMoveWithinBounds m){
                if(state.isOutOfBounds){
                    state.currFloor = state.prevFloor;
                    state.currDirn = Dirn.Stop;
                    state.resetBg;
                    clearConsoleLine;
                }
            },

            /// --- LOG --- ///
            (ClientConnected cc){
                state.clientConnected = cc;
                if(cfg.stopMotorOnDisconnect && !cc){
                    thisTid.send(MotorDirection(Dirn.Stop));
                }
            },
            

            /// --- OTHER --- ///
            
            (LinkTerminated lt){
                assert(false, "Child thread terminated, shutting down...");
            },
            (Variant v){
                assert(false, "Received unknown type " ~ v.to!string ~ ", terminating...");
            }

        );
    }
    } catch(Throwable t){
        writeln(typeid(t).name, "@", t.file, "(", t.line, "): ", t.msg);
    }
}

version(Posix){
    import core.sys.posix.termios;
    __gshared termios oldt;
    __gshared termios newt;
    shared static this(){
        tcgetattr(0, &oldt);
        newt = oldt;
        newt.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(0, TCSANOW, &newt);
    }
    shared static ~this(){
        tcsetattr(0, TCSANOW, &oldt);
    }
}

void stdinGetterProc(Tid receiver){
    try {
    version(Windows){
        import core.sys.windows.wincon;
        import core.sys.windows.winbase;

        SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), ENABLE_PROCESSED_INPUT);
        foreach(ubyte[] buf; stdin.byChunk(1)){
            SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), ENABLE_PROCESSED_INPUT);
            receiver.send(StdinChar(cast(char)buf[0]));
        }

    } else version(Posix){
        import core.stdc.stdio;

        while(true){
            receiver.send(StdinChar(cast(char)getchar()));
        }
    }
    } catch(Throwable t){
        writeln(typeid(t).name, "@", t.file, "(", t.line, "): ", t.msg);
    }
}


void stdinParseProc(Tid receiver){
    try {
    while(true){
        receive(
            (StdinChar c){
                foreach(btnType, keys; cfg.key_orderButtons){
                    int floor = keys.countUntil(c.toLower).to!int;
                    if( (floor != -1) &&
                        !(btnType == BtnType.Up && c == keys[$-1]) &&
                        !(btnType == BtnType.Down && c == keys[0])
                    ){
                        if(c.isUpper){
                            receiver.send(OrderButton(floor, cast(BtnType)btnType, BtnAction.Toggle));
                        } else {
                            receiver.send(OrderButton(floor, cast(BtnType)btnType, BtnAction.Press));
                            addEvent(receiver, cfg.btnDepressedTime, OrderButton(floor, cast(BtnType)btnType, BtnAction.Release));
                        }
                    }
                }

                if(c.toLower == cfg.key_stopButton){
                    if(c.isUpper){
                        receiver.send(StopButton(BtnAction.Toggle));
                    } else {
                        receiver.send(StopButton(BtnAction.Press));
                        addEvent(receiver, cfg.btnDepressedTime, StopButton(BtnAction.Release));
                    }
                }

                if(c == cfg.key_obstruction){
                    receiver.send(ObstructionSwitch());
                }

                if(c == cfg.key_moveUp){
                    receiver.send(MotorDirection(Dirn.Up));
                }
                if(c == cfg.key_moveStop){
                    receiver.send(MotorDirection(Dirn.Stop));
                }
                if(c == cfg.key_moveDown){
                    receiver.send(MotorDirection(Dirn.Down));
                }
                if(c == cfg.key_moveInbounds){
                    receiver.send(ManualMoveWithinBounds());
                }
            }
        );
    }
    } catch(Throwable t){
        writeln(typeid(t).name, "@", t.file, "(", t.line, "): ", t.msg);
    }
}


void networkInterfaceProc(Tid receiver){
    try {
    
    Socket acceptSock = new TcpSocket();

    acceptSock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    acceptSock.bind(new InternetAddress(cfg.port.to!ushort));
    acceptSock.listen(1);

    ubyte[4] buf;

    while(true){
        auto sock = acceptSock.accept();
        receiver.send(ClientConnected(true));
        while(sock.isAlive){
            buf = 0;
            auto n = sock.receive(buf);

            if(n <= 0){
                receiver.send(ClientConnected(false));
                sock.shutdown(SocketShutdown.BOTH);
                sock.close();
            } else {
                switch(buf[0]){
                case 0:
                    receiver.send(ReloadConfig());
                    break;
                case 1:
                    receiver.send(MotorDirection(
                        (buf[1] == 0)   ? Dirn.Stop :
                        (buf[1] < 128)  ? Dirn.Up   :
                                          Dirn.Down
                    ));
                    break;
                case 2:
                    receiver.send(OrderButtonLight(buf[2].to!int, cast(BtnType)buf[1], buf[3].to!bool));
                    break;
                case 3:
                    receiver.send(FloorIndicator(buf[1].to!int));
                    break;
                case 4:
                    receiver.send(DoorLight(buf[1].to!bool));
                    break;
                case 5:
                    receiver.send(StopButtonLight(buf[1].to!bool));
                    break;

                case 6:
                    receiver.send(thisTid, OrderButtonRequest(buf[2].to!int, cast(BtnType)buf[1]));
                    receive((bool v){
                        buf[1..$] = [v.to!ubyte, 0, 0];
                        sock.send(buf);
                    });
                    break;
                case 7:
                    receiver.send(thisTid, FloorSensorRequest());
                    receive((int f){
                        buf[1..$] = (f == -1) ? [0, 0, 0] : [1, cast(ubyte)f, 0];
                        sock.send(buf);
                    });
                    break;
                case 8:
                    receiver.send(thisTid, StopButtonRequest());
                    receive((bool v){
                        buf[1..$] = [v.to!ubyte, 0, 0];
                        sock.send(buf);
                    });
                    break;
                case 9:
                    receiver.send(thisTid, ObstructionRequest());
                    receive((bool v){
                        buf[1..$] = [v.to!ubyte, 0, 0];
                        sock.send(buf);
                    });
                    break;
                default:
                    break;
                }
            }
        }
    }
    
    } catch(Throwable t){
        writeln(typeid(t).name, "@", t.file, "(", t.line, "): ", t.msg);
    }
}















