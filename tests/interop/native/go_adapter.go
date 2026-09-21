package main

import (
 "bufio"
 "bytes"
 "encoding/binary"
 "encoding/hex"
 "fmt"
 "io"
 "math"
 "os"
 "strconv"
 "strings"
 "time"
 mp "github.com/vmihailenco/msgpack/v5"
)

type parser struct { a []string; p int }
func (p *parser) next() string { if p.p>=len(p.a) { panic("missing token") }; s:=p.a[p.p]; p.p++; return s }
func check(e error) { if e!=nil { panic(e) } }
func raw(s string) []byte { if s=="-" {return nil}; b,e:=hex.DecodeString(s);check(e);return b }
func number(s string) int { n,e:=strconv.Atoi(s);check(e);return n }
func encoded(p *parser,e *mp.Encoder,b *bytes.Buffer) {
 switch p.next() {
 case "n": check(e.EncodeNil())
 case "b": check(e.EncodeBool(p.next()=="1"))
 case "i":
  s:=p.next(); if strings.HasPrefix(s,"-") {n,x:=strconv.ParseInt(s,10,64);check(x);check(e.EncodeInt(n))} else {n,x:=strconv.ParseUint(s,10,64);check(x);check(e.EncodeUint(n))}
 case "f": h:=raw(p.next());check(e.EncodeFloat32(math.Float32frombits(binary.BigEndian.Uint32(h))))
 case "d": h:=raw(p.next());check(e.EncodeFloat64(math.Float64frombits(binary.BigEndian.Uint64(h))))
 case "s": check(e.EncodeString(string(raw(p.next()))))
 case "x": h:=raw(p.next()); if h==nil {h=[]byte{}};check(e.EncodeBytes(h))
 case "a": n:=number(p.next());check(e.EncodeArrayLen(n));for i:=0;i<n;i++ {encoded(p,e,b)}
 case "m": n:=number(p.next());check(e.EncodeMapLen(n));for i:=0;i<n*2;i++ {encoded(p,e,b)}
 case "e":
  tag:=int8(number(p.next()));h:=raw(p.next())
  if tag == -1 {
   var sec int64; var ns uint32
   switch len(h) {case 4:sec=int64(binary.BigEndian.Uint32(h));case 8:n:=binary.BigEndian.Uint64(h);sec=int64(n&0x3ffffffff);ns=uint32(n>>34);case 12:ns=binary.BigEndian.Uint32(h);sec=int64(binary.BigEndian.Uint64(h[4:]));default:panic("timestamp length")}
   check(e.EncodeTime(time.Unix(sec,int64(ns))))
  } else {check(e.EncodeExtHeader(tag,len(h)));_,x:=b.Write(h);check(x)}
 default:panic("unknown token")
 }
}
func hx(b []byte) string {if len(b)==0{return "-"};return hex.EncodeToString(b)}
func decoded(d *mp.Decoder) []string {
 c,err:=d.PeekCode();check(err)
 switch {
 case c==0xc0:check(d.DecodeNil());return []string{"n"}
 case c==0xc2 || c==0xc3:n,x:=d.DecodeBool();check(x);if n{return []string{"b","1"}};return []string{"b","0"}
 case c<=0x7f || (c>=0xcc && c<=0xcf):n,x:=d.DecodeUint64();check(x);return []string{"i",strconv.FormatUint(n,10)}
 case c>=0xe0 || (c>=0xd0 && c<=0xd3):n,x:=d.DecodeInt64();check(x);return []string{"i",strconv.FormatInt(n,10)}
 case c==0xca:n,x:=d.DecodeFloat32();check(x);return []string{"f",fmt.Sprintf("%08x",math.Float32bits(n))}
 case c==0xcb:n,x:=d.DecodeFloat64();check(x);return []string{"d",fmt.Sprintf("%016x",math.Float64bits(n))}
 case (c>=0xa0 && c<=0xbf)||(c>=0xd9 && c<=0xdb):n,x:=d.DecodeString();check(x);return []string{"s",hx([]byte(n))}
 case c>=0xc4 && c<=0xc6:n,x:=d.DecodeBytes();check(x);return []string{"x",hx(n)}
 case (c>=0x90 && c<=0x9f)||c==0xdc||c==0xdd:
  n,x:=d.DecodeArrayLen();check(x);r:=[]string{"a",strconv.Itoa(n)};for i:=0;i<n;i++ {r=append(r,decoded(d)...)};return r
 case (c>=0x80 && c<=0x8f)||c==0xde||c==0xdf:
  n,x:=d.DecodeMapLen();check(x);r:=[]string{"m",strconv.Itoa(n)};for i:=0;i<n*2;i++ {r=append(r,decoded(d)...)};return r
 case (c>=0xc7 && c<=0xc9)||(c>=0xd4 && c<=0xd8):
  tag,n,x:=d.DecodeExtHeader();check(x);h:=make([]byte,n);check(d.ReadFull(h));return []string{"e",strconv.Itoa(int(tag)),hx(h)}
 default:panic("unknown marker")
 }
}
func process(line string)(result string) {
 defer func(){if r:=recover();r!=nil {result="X "+strings.ReplaceAll(fmt.Sprint(r),"\n"," ")}}()
 a:=strings.Fields(line);if len(a)==0 {panic("empty request")}
 if a[0]=="E" {var b bytes.Buffer;p:=parser{a:a[1:]};encoded(&p,mp.NewEncoder(&b),&b);if p.p!=len(p.a){panic("trailing tokens")};return "H "+hex.EncodeToString(b.Bytes())}
 if a[0]=="D" {r:=bytes.NewReader(raw(a[1]));d:=mp.NewDecoder(r);v:=decoded(d);_,x:=d.PeekCode();if x!=io.EOF {panic("trailing data")};return "V "+strings.Join(v," ")}
 panic("unknown operation")
}
func main(){s:=bufio.NewScanner(os.Stdin);s.Buffer(make([]byte,4096),64*1024*1024);for s.Scan(){fmt.Println(process(s.Text()))};check(s.Err())}
