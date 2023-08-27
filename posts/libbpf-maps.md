*This post was originally on my employer's website https://cmd.com, but
the website is no longer up due Elastic's acquisition of Cmd. I got
permission to move this post to my personal blog. The old title used to
be "How Zig Makes libbpf Easy", but I've opted for something a bit more
direct here.*

*Also it's been a couple years since the post, I've gone onto working with
embedded systems with Zig and haven't had enough time to flesh out BPF. Zig is
promising for BPF programs, and the conclusions of this post are incorrect with
hindsight. The next step for BPF in zig is adding functionality to help with
BTF generation. BTF is automatically generated for Zig, however we need a way
to rename the debug info for a type so that it matches the corresponding C
type. (Eg. in Zig debug info a type might be named `.bpf.kernel.TaskStruct`,
and we need a way to make it `task_struct`.*

Heads up, this is a fairly detailed deep dive into some of what libbpf does and
knowledge on BPF is required. Luckily I have you covered with
[this](https://www.youtube.com/watch?v=vZYKq3Dvv0g) talk I gave on BPF.

libbpf is a C library that gives you a nice API for opening and loading BPF
bytecode contained in Executable and Linkable Format (ELF) files. You
declaratively lay out your components in a single compilation unit: BPF maps as
global variables, programs as functions. This gets compiled into your ELF, and
the loader does everything else for you, even attach programs to certain hook
points.This is a huge improvement over BCC where you’d write a C based BPF
program in a python string literal, as well as use python as a preprocessor.

We’re going to learn about one of the operations libbpf automates when loading
your bytecode. BPF maps are used as general-purpose storage between userspace
and executions of BPF programs. When creating a map we receive a file
descriptor and that needs to be stored in the binary blob containing a program
before that it’s loaded into the kernel. Luckily the information on how to do
this is stored in the ELF file created from compiling your BPF code and libbpf
knows how to parse this file so that it can orchestrate the above.
Understanding these mechanics will enable developers to write their own loaders
and improve their mental model of the BPF subsystem.

Furthermore, all code in this article will be written in Zig, a simple language
with top notch error handling, compile-time capabilities, and a powerful build
system. At the end, if you want to take a closer look at the code, you can find
it in this [repo](https://github.com/mattnite/zig-bpf-intro). Don’t worry if you
haven’t heard of Zig before, because you already know how to read it.

## Challenges learning BPF

One of the challenges of learning BPF, and libbpf is no exception to this, is
that large swaths of it are undocumented (thought that is starting to
[improve](http://ebpf.io/). When I first started learning BPF this library
constantly posed an opaque barrier to understanding. My goal was to learn how
userspace should correctly instrument specific syscalls, so I dove into the
source to find out. While this was going on I was also learning Zig, and
discovered that it was able to produce decent bytecode out-of-the-box™ (that
is, no [hacks](https://blog.redsift.com/labs/oxidised-ebpf-ii-taming-llvm/)
required).

There are a large number of other operations that libbpf does, for example,
somehow loading the read-only section of the binary separate from everything
else. It also expects programs to have their own section using a naming scheme
that declares how/where the program needs to be loaded.
[Here](https://github.com/libbpf/libbpf/blob/b6dd2f2b7df4d3bd35d64aaf521d9ad18d766f53/src/libbpf.c#L8004)
you can find a massive table laying out this information I have yet to
decipher, but I digress, let’s get to our BPF program.

== Baby's first BPF Program

```zig
const std = @import("std");
const mem = std.mem
const bpf = @import("bpf");

export var events linksection("maps") = PerfEventArray.init(256, 0);

export fn bpf_prog(ctx: *bpf.SkBuff) linksection("socket1") c_int {
    var time = bpf.ktime_get_ns();
    events.event_output(ctx, bpf.F_CURRENT_CPU, mem.asBytes(&time)) catch {};
    return 0;
}
```

So this is a pretty innocuous example, all we’re doing is getting time through
a BPF Helper function, and then writing it to a Perf Event Buffer, but the
important part is that the program is referencing a BPF map. Building this is
extremely simple, Zig build scripts are written in Zig (a nice
[resource](https://ziglearn.org/chapter-3/) on that), and all we have to do is
target a freestanding BPF architecture, and I’ve set the endianness to match
whatever we’re targeting for the main userspace program.

```zig
const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const obj = b.addObject("probe", "src/probe.zig");
    obj.setTarget(std.zig.CrossTarget{
        .cpu_arch = switch ((target.cpu_arch orelse builtin.arch).endian()) {
            .Big => .bpfeb,
            .Little => .bpfel,
        },
        .os_tag = .freestanding,
    });

    obj.setBuildMode(.ReleaseFast);
    obj.setOutputDir("src");
}
```

You’ll also notice that I’m outputting the compiled object file to the `src`
directory. That’s because Zig has the `@embedFile()` builtin which will let me
embed a file as an array of bytes within the main program, this way I have a
single binary at the end of the build process.

## Parsing ELF

![ELF](../images/elf.gif)

We’ll be attaching the BPF program to a raw socket on the loopback device so
that it’s run when packets are sent or received. Now let’s inspect the ELF
(only showing what’s important):

```
$ llvm-objdump --section-headers src/probe.o

src/probe.o:    file format ELF64-BPF

Sections:
Idx Name                Size     VMA              Type
  0                     00000000 0000000000000000
  1 .text               00000000 0000000000000000 TEXT
  2 socket1             00000070 0000000000000000 TEXT
  3 .relsocket1         00000010 0000000000000000
  4 maps                00000014 0000000000000000 DATA
...
 15 .BTF                00000201 0000000000000000
 16 .BTF.ext            00000090 0000000000000000
 17 .rel.BTF.ext        00000060 0000000000000000
...
 23 .symtab             00001920 0000000000000000
 24 .shstrtab           00000135 0000000000000000
 25 .strtab             00000017 0000000000000000
```

Section `socket1` contains our program and can be seen as an array of
instructions. `maps` similarly is an array of BPF map definitions (in our case
and array of one map):

```zig
pub const Insn = packed struct {
    code: u8,
    dst: u4,
    src: u4,
    off: i16,
    imm: i32,
};

pub const MapDef = extern struct {
    type: u32,
    key_size: u32,
    value_size: u32,
    max_entries: u32,
    map_flags: u32,
};
```

The loader can read the `maps` section directly and use `BPF_MAP_CREATE` with
the `bpf()` syscall to create all of our maps. Next comes the cool part, we
have that array of instructions that makes up our program:

```
$ llvm-objdump -d src/probe.o

src/probe.o:    file format ELF64-BPF

Disassembly of section socket1:

0000000000000000 bpf_prog:
       0:       bf 16 00 00 00 00 00 00 r6 = r1
       1:       85 00 00 00 05 00 00 00 call 5
       2:       7b 0a f8 ff 00 00 00 00 *(u64 *)(r10 - 8) = r0
       3:       bf a4 00 00 00 00 00 00 r4 = r10
       4:       07 04 00 00 f8 ff ff ff r4 += -8
       5:       bf 61 00 00 00 00 00 00 r1 = r6
       6:       18 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 r2 = 0 ll
       8:       18 03 00 00 ff ff ff ff 00 00 00 00 00 00 00 00 r3 = 4294967295 ll
      10:       b7 05 00 00 08 00 00 00 r5 = 8
      11:       85 00 00 00 19 00 00 00 call 25
      12:       b7 00 00 00 00 00 00 00 r0 = 0
      13:       95 00 00 00 00 00 00 00 exit
```

I won’t go into detail for each instruction because the
[Cilium BPF Reference](https://web.archive.org/web/20210924055625/https://docs.cilium.io/en/latest/bpf/)
has a lot of great information that you can review yourself, but
the one we’re interested in is #6. According to the signature of the
`perf_event_output()` Helper we’re supposed to be loading a “map pointer” into
register 2, and in the code we do give it the address of the map, but the
instruction loads r2 with the value zero, or null. What we actually need to do
for loading is replace the immediate value of zero with the file descriptor of
the map — super funky. From the loader’s perspective it’s able to determine
exactly which map goes where with the `.relsocket1` section which contains
links between entries in the `.symtab` section (symbols) and offsets within the
program code. Here is a chunk of code showing my simplified Zig runtime loader
rewriting those immediate values:

```zig
    for (self.progs.items) |*prog| {
        const rel_name = try std.mem.join(self.allocator, "", &[_][]const u8{ ".rel", prog.name });
        defer self.allocator.free(rel_name);

        const rel_section: *Elf.Section = for (self.elf.relos.items) |relo| {
            if (mem.eql(u8, self.elf.get_section_name(relo), rel_name)) {
                break relo;
            }
        } else continue;

        for (std.mem.bytesAsSlice(Elf64_Rel, rel_section.data)) |relo| {
            const insn_idx = relo.r_offset / @sizeOf(BPF.Insn);
            const symbol = self.elf.get_sym_idx(@truncate(u32, relo.r_info >> 32));
            const map_name = self.elf.get_str(symbol.st_name);

            const map_fd = for (self.maps.items) |m| {
                if (mem.eql(u8, m.name, map_name)) {
                    break m.fd.?;
                }
            } else continue;

            prog.insns[insn_idx].src = BPF.PSEUDO_MAP_FD;
            prog.insns[insn_idx].imm = map_fd;
        }
    }
```

## Next Steps: Leveraging Zig’s comptime Features

Down the road I’m going to create a loader that takes advantage of Zig’s
comptime abilities to parse the embedded object files. This would add compile
time verification of the BPF environment’s contents, remove ELF parsing code
from our executables and reduce the size of what’s being embedded — a full
implementation of this equivalent is ways off, but I do have a proof-of-concept
in our main program that asserts at compile-time that the embedded `probe.o`
file contains the `socket1` section. If it didn’t contain the section we would
get a compile error.

## Conclusion

libbpf is becoming the standard in how BPF is used in production, and while
it’s great to have well known, trusted tools it’s also important to understand
how our tools work and where they may fall short. I’m going to take this
knowledge and try to leverage Zig’s comptime abilities to improve communicating
the BPF environment to userspace and others might also find novel new ways to
do this as well. BPF tech is moving fast and I’m excited for the future.
