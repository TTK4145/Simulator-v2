Simulator mkII
==============

This simulator is an extension to `elev.c` that lets you use both the actual elevator at the real-time lab, and a simulated elevator.

The simulated elevator is a server which is intended to be run in its own window. Communication with the server is done over TCP. `elev.c` has been modified to act as a client, where the network portion is written with linux in mind (as this is what you use at the lab, and libcomedi also only works on linux). However, it is possible to write a client in another language, thus avoiding the OS-specific C code entirely.

The server is written in D, so you will need a D compiler to run it. I recommend using the dmd compiler (since this is the only one I have tested it with), which you can get from [The D lang website](http://dlang.org/download.html#dmd).

Main features:
 - 2 to 9 floors: Test the elevator with a different number of floors
 - Fully customizable controls: Dvorak and qwertz users rejoice!
 - Full-time manual motor override: Control the motor directly, simulating motor stop or unexpected movement.
 - Button hold: Hold down buttons by using uppercase letters.
 


Usage
=====

API Changes for `elev.c`
------------------------

The only difference is:
 - `elev_init(elev_type e);`
 - Takes either `ET_Comedi` or `ET_Simulation`


Running the server
------------------

The server is intended to run in its own window, as it also takes keyboard input to simulate button presses. The server should not need to be restarted if the client is restarted.

Running:
 - `rdmd sim_server.d`, if `simulator.con` is in the folder you are running `rdmd` from, or
 - `rdmd sim_server.d [configfile]`, to specify a another config file.


Configuration options
---------------------

See [simulator.con](simulator.con) for all the config options.

Default keyboard controls
-------------------------

 - Up: `qwertyui`
 - Down: `sdfghjkl`
 - Cab: `zxcvbnm,.`
 - Stop: `p`
 - Obstruction: `-`
 - Motor manual override: Down: `7`, Stop: `8`, Up: `9`

Up, down, cab and stop button can be toggled (and thereby held down) by using uppercase letters.


Display
-------

```
+-----------+-----------------+
|           |        #>       |
| Floor     |  0   1*  2   3  |
+-----------+-----------------+-----------+
| Hall Up   |  *   -   -      | Door:   - |
| Hall Down |      -   -   *  | Stop:   - |
| Cab       |  -   -   *   -  | Obstr:  ^ |
+-----------+-----------------+---------43+
```

The ascii-art-style display is updated whenever the state of the simulated elevator is updated.

A print count (number of times a new state is printed) is shown in the lower right corner of the display. Try to avoid writing to the (simulated) hardware if nothing has happened. A jump of 20-50 in the printcount is fine (even expected), but if there are larger jumps or there is a continuous upward count, it may be time to re-evaluate some design choices.



Creating your own client
========================

You can use the simulator entirely without the C client code by creating your own client in the language of your choice. The binary protocol for interfacing with the server is outlined below:

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
            <td><em>Reload config</em></td>
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


Since interfacing is done over TCP, you can also use command-line utilities to interface with the simulator server. For example, to read the current floor:
```bash
echo -e '\x07\x00\x00\x00' | netcat localhost 15657 | od -tx1
```






