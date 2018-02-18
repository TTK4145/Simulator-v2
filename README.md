Simulator mkII
==============

This simulator is a drop-in alternative to the elevator hardware server that interfaces to the hardware at the lab. Communication to the simulator is over TCP, with the same protocol as the hardware server.

Main features:
 - 2 to 9 floors: Test the elevator with a different number of floors
 - Fully customizable controls: Dvorak and azerty users rejoice!
 - Full-time manual motor override: Control the motor directly, simulating motor stop or unexpected movement.
 - Button hold: Hold down buttons by using uppercase letters.

 
Executables
===========
 
[Executables for Windows and Linux can be found here](https://github.com/TTK4145/Simulator-v2/releases/latest)
 
The server is intended to run in its own window, as it also takes keyboard input to simulate button presses. The server should not need to be restarted if the client is restarted.

Remember to `chmod +x SimElevatorServer` in order to give yourself permission to run downloaded files.
 
Usage
=====

Configuration options
---------------------

The simulator has several configuration options, which you can find [listed here](simulator.con). The most relevant options are:
 - `--port`: This is the TCP port used to connect to the simulator, which defaults to 15657.  
 You should change this number in order to not interfere with other people's running simulators.  
 You can start multiple simulators with different port numbers to run multiple elevators on a single machine.
 - `--numfloors`: The number of floors 2 to 9), which defaults to 4.
 
Options passed on the command line (eg. `./SimElevatorServer --port 12345`) override the options in the the `simulator.con` config file, which in turn override the defaults baked in to the program. `simulator.con` must exist in the same folder as the executable in order to be loaded.

Options are not case sensitive.
 

Default keyboard controls
-------------------------

 - Up: `qwertyui`
 - Down: `sdfghjkl`
 - Cab: `zxcvbnm,.`
 - Stop: `p`
 - Obstruction: `-`
 - Motor manual override: Down: `7`, Stop: `8`, Up: `9`
 - Move elevator back in bounds (away from the end stop switches): `0`

Up, down, cab and stop buttons can be toggled (and thereby held down) by using uppercase letters.


Display
-------

```
+-----------+-----------------+
|           |        #>       |
| Floor     |  0   1*  2   3  |Connected
+-----------+-----------------+-----------+
| Hall Up   |  *   -   -      | Door:   - |
| Hall Down |      -   -   *  | Stop:   - |
| Cab       |  -   -   *   -  | Obstr:  ^ |
+-----------+-----------------+---------43+
```

The ascii-art-style display is updated whenever the state of the simulated elevator is updated.

A print count (number of times a new state is printed) is shown in the lower right corner of the display. Try to avoid writing to the (simulated) hardware if nothing has happened. A jump of 20-50 in the printcount is fine (even expected), but if there are larger jumps or there is a continuous upward count, it may be time to re-evaluate some design choices.

Since the simulator changes the terminal input mode (in order to read key presses without you having to press Enter), the input mode is sometimes broken if the simulator does not quit properly. Type `reset` and hit Enter to reset the terminal completely if this happens.

Compiling from source
---------------------

The server is written in D, so you will need a D compiler to run it. I recommend using the dmd compiler (since this is the only one I have tested it with), which you can get from [The D lang website](http://dlang.org/download.html#dmd).

Compile with `dmd -w -g src/sim_server.d src/timer_event.d -ofSimElevatorServer`


Creating your own client
========================

If your client works with the elevator hardware server, then it should work with the simulator with no changes. 

Protocol
--------

 - All TCP messages must have a length of 4 bytes
 - The instructions for reading from the hardware send replies that are 4 bytes long, where the last byte is always 0
 - The instructions for writing to the hardware do not send any replies

<table>
    <tbody>
        <tr>
            <td><strong>Writing</strong></td>
            <td align="center" colspan="4">Instruction</td>
            <td align="center" colspan="0" rowspan="7"></td>
        </tr>
        <tr>
            <td><em>Reload config (file and args)</em></td>
            <td>&nbsp;&nbsp;0&nbsp;&nbsp;</td>
            <td>X</td>
            <td>X</td>
            <td>X</td>
        </tr>
        <tr>
            <td><em>Motor direction</em></td>
            <td>&nbsp;&nbsp;1&nbsp;&nbsp;</td>
            <td>direction<br>[-1 (<em>255</em>),0,1]</td>
            <td>X</td>
            <td>X</td>
        </tr>
        <tr>
            <td><em>Order button light</em></td>
            <td>&nbsp;&nbsp;2&nbsp;&nbsp;</td>
            <td>button<br>[0,1,2]</td>
            <td>floor<br>[0..NF]</td>
            <td>value<br>[0,1]</td>
        </tr>
        <tr>
            <td><em>Floor indicator</em></td>
            <td>&nbsp;&nbsp;3&nbsp;&nbsp;</td>
            <td>floor<br>[0..NF]</td>
            <td>X</td>
            <td>X</td>
        </tr>
        <tr>
            <td><em>Door open light</em></td>
            <td>&nbsp;&nbsp;4&nbsp;&nbsp;</td>
            <td>value<br>[0,1]</td>
            <td>X</td>
            <td>X</td>
        </tr>
        <tr>
            <td><em>Stop button light</em></td>
            <td>&nbsp;&nbsp;5&nbsp;&nbsp;</td>
            <td>value<br>[0,1]</td>
            <td>X</td>
            <td>X</td>
        </tr>
        <tr>
            <td><strong>Reading</strong></td>
            <td align="center" colspan="4">Instruction</td>
            <td></td>
            <td align="center" colspan="4">Output</td>
        </tr>
        <tr>
            <td><em>Order button</em></td>
            <td>&nbsp;&nbsp;6&nbsp;&nbsp;</td>
            <td>button<br>[0,1,2]</td>
            <td>floor<br>[0..NF]</td>
            <td>X</td>
            <td align="right"><em>Returns:</em></td>
            <td>6</td>
            <td>pressed<br>[0,1]</td>
            <td>0</td>
            <td>0</td>
        </tr>
        <tr>
            <td><em>Floor sensor</em></td>
            <td>&nbsp;&nbsp;7&nbsp;&nbsp;</td>
            <td>X</td>
            <td>X</td>
            <td>X</td>
            <td align="right"><em>Returns:</em></td>
            <td>7</td>
            <td>at floor<br>[0,1]</td>
            <td>floor<br>[0..NF]</td>
            <td>0</td>
        </tr>
        <tr>
            <td><em>Stop button</em></td>
            <td>&nbsp;&nbsp;8&nbsp;&nbsp;</td>
            <td>X</td>
            <td>X</td>
            <td>X</td>
            <td align="right"><em>Returns:</em></td>
            <td>8</td>
            <td>pressed<br>[0,1]</td>
            <td>0</td>
            <td>0</td>
        </tr>
        <tr>
            <td><em>Obstruction switch</em></td>
            <td>&nbsp;&nbsp;9&nbsp;&nbsp;</td>
            <td>X</td>
            <td>X</td>
            <td>X</td>
            <td align="right"><em>Returns:</em></td>
            <td>9</td>
            <td>active<br>[0,1]</td>
            <td>0</td>
            <td>0</td>
        </tr>
        <tr>
            <td colspan="0"><em>NF = Num floors. X = Don't care.</em></td>
        </tr>
    </tbody>
</table>

Button types (for reading the button and setting the button light) are in the order `0: Hall Up`, `1: Hall Down`, `2: Cab`.

Since interfacing is done over TCP, you can also use command-line utilities to interface with the simulator server. For example, to read the current floor:
```bash
echo -e '\x07\x00\x00\x00' | netcat localhost 15657 | od -tx1
```






