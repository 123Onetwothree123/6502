#!/usr/bin/python3
import sys,argparse

##########################################################################
##########################################################################
#
# shellcmd.py - Python 3 script that performs various shell
# command-type operations
# 
# Copyright (C) 2019 Tom Seddon
# 
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY# without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see
# <https://www.gnu.org/licenses/>.
#
##########################################################################
##########################################################################

g_verbose=False

def pv(x):
    if g_verbose:
        sys.stderr.write(x)
        sys.stderr.flush()

##########################################################################
##########################################################################

def cp_cmd(options):
    import shutil
    
    shutil.copy(options.src,options.dest)

##########################################################################
##########################################################################
    
def rmtree_cmd(options):
    import os,shutil
    
    if os.path.isdir(options.path): shutil.rmtree(options.path)

##########################################################################
##########################################################################

def rmfile_cmd(options):
    import os

    for path in options.paths:
        try: os.unlink(path)
        except FileNotFoundError:
            if not options.force:
                sys.stderr.write('''FATAL: file doesn't exist: %s'''%path)
                sys.exit(1)

##########################################################################
##########################################################################

def mkdir_cmd(options):
    import os
    
    for path in options.paths:
        path=os.path.normpath(path)
        if not os.path.isdir(path): os.makedirs(path)

##########################################################################
##########################################################################

def touch_cmd(options):
    import os
    
    if not os.path.isfile(options.path):
        with open(options.path,'wb'): pass

    os.utime(options.path,None)  # None = now

##########################################################################
##########################################################################

def strftime_cmd(options):
    import datetime
    
    fmt=options.fmt
    if options.directive_prefix is not None:
        fmt=fmt.replace(options.directive_prefix,'%')

    pv('strftime format used: ``%s\'\'\n'%fmt)
    print(datetime.datetime.now().strftime(fmt))

##########################################################################
##########################################################################

def sha1_cmd(options):
    import hashlib
    
    with open(options.path,'rb') as f: data=f.read()

    for ignore in options.ignores:
        data=data.replace(bytes(ignore,'utf-8'),b'')

    m=hashlib.sha1()
    m.update(data)
    print('%s  %s'%(m.hexdigest(),options.path))

##########################################################################
##########################################################################

def blank_line_cmd(options):
    print()

##########################################################################
##########################################################################

def cat_cmd(options):
    for path in options.paths:
        with open(path,'rt') as f: sys.stdout.write(f.read())

##########################################################################
##########################################################################
        
def realpath_cmd(options):
    import os
    
    print(os.path.realpath(options.path))

##########################################################################
##########################################################################
    
def stat_cmd(options):
    import os,glob

    seen_paths=set()
    paths=[]
    for path in options.paths:
        matches=glob.glob(path)
        for match in matches:
            if match not in seen_paths:
                paths.append(match)
                seen_paths.add(match)
    
    for path in paths:
        try: st=os.stat(path)
        except: st=None

        if options.basename: path=os.path.basename(path)

        str=''
        
        str+='%10s '%('?' if st is None else '{:,}'.format(st.st_size))
        
        if options.hex_size:
            str+='%10s '%('' if st is None else '0x%x'%st.st_size)

        str+=' '+path

        if options.size_budget is not None and st is not None:
            str+=' ({:,} left)'.format(options.size_budget-st.st_size)

        print(str)

##########################################################################
##########################################################################

def whoami_cmd(options):
    import getpass
    print(getpass.getuser())

##########################################################################
##########################################################################

def move_cmd(options):
    import os,shutil
    
    # I don't think having move and rename as the same action is
    # good...
    if not os.path.isdir(options.dest):
        sys.stderr.write('FATAL: not a folder: %s\n'%options.dest)
        sys.exit(1)
        
    shutil.move(options.src,options.dest)

##########################################################################
##########################################################################

def cmp_cmd(options):
    with open(options.path1,'rb') as f: a=f.read()
    with open(options.path2,'rb') as f: b=f.read()
    if a!=b:
        if g_verbose:
            sys.stderr.write(
                'FATAL: files differ: %s and %s\n'%(options.path1,
                                                    options.path2))
        sys.exit(1)

##########################################################################
##########################################################################

def split_cmd(options):
    suffix=0
    with open(options.path,'rb') as f:
        while True:
            data=f.read(options.bytes)
            if len(data)>0:
                output_path='%s%d'%(options.prefix,suffix)
                with open(output_path,'wb') as f2: f2.write(data)
            if len(data)<options.bytes: break
            suffix+=1

##########################################################################
##########################################################################

def concat2(options,output_f):
    for path in options.input_paths:
        with open(path,'rb') as f: data=f.read()
        if options.pad is not None:
            if len(data)>options.pad:
                sys.stderr.write(
                    'FATAL: file larger than %d bytes: %s\n'%(options.pad,
                                                              path))
                sys.exit(1)
            data+=bytes(options.pad-len(data))
        if output_f is not None: output_f.write(data)

def concat_cmd(options):
    if options.output:
        with open(options.output,'wb') as f: concat2(options,f)
    else: concat2(options,None)


##########################################################################
##########################################################################

def rename_cmd(options):
    import os

    # problem on Windows, but not an issue on Unix in all cases.
    if os.path.isfile(options.dest) or os.path.isdir(options.dest):
        sys.stderr.write('FATAL: already exists: %s\n'%options.dest)
        sys.exit(1)
        
    os.rename(options.src,options.dest)

##########################################################################
##########################################################################

def shellcmd(options):
    import glob
    
    global g_verbose
    g_verbose=options.verbose

    options.fun(options)

##########################################################################
##########################################################################

def auto_int(x): return int(x,0)

def main(argv):
    parser=argparse.ArgumentParser()

    parser.add_argument('-v','--verbose',action='store_true',help='be more verbose')
    parser.set_defaults(fun=None)

    subparsers=parser.add_subparsers(title='sub-command help')

    blank_line=subparsers.add_parser('blank-line',help='print blank line')
    blank_line.set_defaults(fun=blank_line_cmd)

    cat=subparsers.add_parser('cat',help='print file(s) to standard output')
    cat.add_argument('paths',metavar='FILE',nargs='+',help='file(s) to print')
    cat.set_defaults(fun=cat_cmd)

    cmp=subparsers.add_parser('cmp',help='compare smallish files as binary')
    cmp.add_argument('path1',metavar='A',help='first file')
    cmp.add_argument('path2',metavar='B',help='second file')
    cmp.set_defaults(fun=cmp_cmd)

    concat=subparsers.add_parser('concat',help='''concatenate binary files''')
    concat.add_argument('--pad',type=auto_int,metavar='N',help='''pad each file (if required) to %(metavar)s bytes. Fail if file is larger''')
    concat.add_argument('-o','--output',metavar='FILE',help='''write output to %(metavar)s''')
    concat.add_argument('input_paths',nargs='+',metavar='FILE',help='''read input from %(metavar)s''')
    concat.set_defaults(fun=concat_cmd)

    cp=subparsers.add_parser('copy-file',help='copy file')
    cp.add_argument('src',metavar='SRC',help='file to copy from')
    cp.add_argument('dest',metavar='DEST',help='file/folder path to copy to')
    cp.set_defaults(fun=cp_cmd)

    mkdir=subparsers.add_parser('mkdir',help='create folder structure')
    mkdir.add_argument('paths',metavar='FOLDER',default=[],nargs='+',help='folder structure to create')
    mkdir.set_defaults(fun=mkdir_cmd)

    move=subparsers.add_parser('move',help='move folder/file')
    move.add_argument('src',metavar='SRC',help='''folder/file to move''')
    move.add_argument('dest',metavar='DEST',help='''folder to move it to''')
    move.set_defaults(fun=move_cmd)

    realpath=subparsers.add_parser('realpath',help='print real path of file')
    realpath.add_argument('path',metavar='PATH',help='path')
    realpath.set_defaults(fun=realpath_cmd)

    rename=subparsers.add_parser('rename',help='rename folder/file')
    rename.add_argument('src',metavar='SRC',help='''old name''')
    rename.add_argument('dest',metavar='DEST',help='''new name''')
    rename.set_defaults(fun=rename_cmd)

    rmfile=subparsers.add_parser('rm-file',help='remove files')
    rmfile.add_argument('-f','--force',action='store_true',help='''don't fail if file doesn't exist''')
    rmfile.add_argument('paths',metavar='FILE',default=[],nargs='+',help='path of file to remove')
    rmfile.set_defaults(fun=rmfile_cmd)

    rmtree=subparsers.add_parser('rm-tree',help='remove folder tree')
    rmtree.add_argument('path',metavar='FOLDER',help='path of folder to remove')
    rmtree.set_defaults(fun=rmtree_cmd)

    sha1=subparsers.add_parser('sha1',help='print SHA1 digest of file')
    sha1.add_argument('--ignore',dest='ignores',action='append',default=[],help='''substring to ignore - will be removed from data before doing the SHA1''')
    sha1.add_argument('path',metavar='FILE',help='file to process')
    sha1.set_defaults(fun=sha1_cmd)

    split=subparsers.add_parser('split',help='split file into parts')
    split.add_argument('path',metavar='FILE',help='''read data from %(metavar)s''')
    split.add_argument('prefix',metavar='PREFIX',help='''write data to file(s) named after %(metavar)s''')
    split.add_argument('-b','--bytes',metavar='SIZE',help='''write max %(metavar)s byte(s) per output file''',required=True,type=auto_int)
    split.set_defaults(fun=split_cmd)

    stat=subparsers.add_parser('stat',help='print human-readable file info, like dir or ls -l')
    stat.add_argument('paths',metavar='PATH',default=[],nargs='+',help='''path(s) to list''')
    stat.add_argument('--basename',action='store_true',help='''only show file basename''')
    # I just happened to need this - feels like there should really be
    # some kind of format string-type approach here?
    stat.add_argument('--hex-size',action='store_true',help='''print size in hex''')
    stat.add_argument('--size-budget',type=auto_int,default=None,help='''show remaining headroom''')
    stat.set_defaults(fun=stat_cmd)
    
    strftime=subparsers.add_parser('strftime',help='format date like strftime/date +XXX')
    strftime.add_argument('-d','--directive-prefix',default=None,help='directive prefix used in place of %%')
    strftime.add_argument('fmt',metavar='FMT',help='strftime format string')
    strftime.set_defaults(fun=strftime_cmd)

    touch=subparsers.add_parser('touch',help='update file modified time, creating file if non-existent')
    touch.add_argument('path',metavar='FILE',help='file to touch')
    touch.set_defaults(fun=touch_cmd)

    whoami=subparsers.add_parser('whoami',help='''print current user''')
    whoami.set_defaults(fun=whoami_cmd)

    options=parser.parse_args(argv)
    if options.fun is None:
        parser.print_help()
        sys.exit(1)

    shellcmd(options)

##########################################################################
##########################################################################

if __name__=='__main__': main(sys.argv[1:])
