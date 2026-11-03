import {encode,decode,ExtData,ExtensionCodec} from '@msgpack/msgpack';
import {createInterface} from 'node:readline';

const codec=new ExtensionCodec();
// Preserve seconds/nanoseconds as raw extension bytes instead of JS Date.
codec.register({type:-1,encode:()=>null,decode:b=>new ExtData(-1,b)});
const unhex=s=>new Uint8Array(Buffer.from(s==='-'?'':s,'hex'));
const hex=b=>Buffer.from(b).toString('hex')||'-';
class Unsupported extends Error {}
function input(p,state) {
 const t=p.shift();
 switch(t){
 case 'n':return null;
 case 'b':return p.shift()==='1';
 case 'i':return BigInt(p.shift());
 case 'f':case 'd':{
  const b=unhex(p.shift());const v=new DataView(b.buffer,b.byteOffset,b.byteLength);
  state.floatKinds.add(t);return t==='f'?v.getFloat32(0):v.getFloat64(0);
 }
 case 's':return new TextDecoder('utf-8',{fatal:true}).decode(unhex(p.shift()));
 case 'x':return unhex(p.shift());
 case 'a':{const n=Number(p.shift());return Array.from({length:n},()=>input(p,state));}
 case 'm':{
  const n=Number(p.shift()),o=Object.create(null);
  for(let i=0;i<n;i++){
   const k=input(p,state),v=input(p,state);
   if(typeof k!=='string')throw new Unsupported('JS object mapping requires string keys');
   if(Object.hasOwn(o,k))throw new Unsupported('JS object mapping cannot preserve duplicate keys');
   o[k]=v;
  }return o;
 }
 case 'e':{const tag=Number(p.shift());return new ExtData(tag,unhex(p.shift()));}
 default:throw Error('unknown token');
 }
}
function output(v){
 if(v===null)return ['n'];
 if(typeof v==='boolean')return ['b',v?'1':'0'];
 if(typeof v==='bigint')return ['i',String(v)];
 // JS has one numeric host type. Integer-vs-float needs the source marker annotation below.
 if(typeof v==='number')return ['d',(()=>{const b=Buffer.alloc(8);b.writeDoubleBE(v);return b.toString('hex');})()];
 if(typeof v==='string')return ['s',hex(Buffer.from(v))];
 if(v instanceof ExtData)return ['e',String(v.type),hex(v.data)];
 if(v instanceof Uint8Array)return ['x',hex(v)];
 if(Array.isArray(v))return ['a',String(v.length),...v.flatMap(output)];
 return ['m',String(Object.keys(v).length),...Object.entries(v).flatMap(([k,x])=>[...output(k),...output(x)])];
}
// On decode the native library returns JS number for small integer markers too.
// Preserve family information using the already-decoded values plus a marker-only traversal.
function annotate(wire,value){
 let pos=0;
 const view=new DataView(wire.buffer,wire.byteOffset,wire.byteLength);
 function width(n){let v=0;for(let i=0;i<n;i++)v=v*256+wire[pos++];return v;}
 function walk(v){
  const c=wire[pos++];
  if(c<=0x7f||c>=0xe0)return ['i',String(v)];
  if(c>=0xcc&&c<=0xd3){pos+=[1,2,4,8,1,2,4,8][c-0xcc];return ['i',String(v)];}
  if(c===0xca||c===0xcb){pos+=c===0xca?4:8;return output(v);}
  if(c===0xc0||c===0xc2||c===0xc3)return output(v);
  if((c>=0xa0&&c<=0xbf)||(c>=0xd9&&c<=0xdb)){const n=c<=0xbf?c-0xa0:width([1,2,4][c-0xd9]);pos+=n;return output(v);}
  if(c>=0xc4&&c<=0xc6){const n=width([1,2,4][c-0xc4]);pos+=n;return output(v);}
  if((c>=0xc7&&c<=0xc9)||(c>=0xd4&&c<=0xd8)){const n=c<=0xc9?width([1,2,4][c-0xc7]):[1,2,4,8,16][c-0xd4];pos+=1+n;return output(v);}
  if((c>=0x90&&c<=0x9f)||c===0xdc||c===0xdd){const n=c<=0x9f?c-0x90:width(c===0xdc?2:4);return ['a',String(n),...v.flatMap(walk)];}
  if((c>=0x80&&c<=0x8f)||c===0xde||c===0xdf){
   const n=c<=0x8f?c-0x80:width(c===0xde?2:4), keys=Object.keys(v);
   if(keys.length!==n)throw new Unsupported('JS object mapping changed map cardinality');
   // String-only keys and insertion order are required by this adapter's profile.
   const r=['m',String(n)];
   for(const k of keys){const marker=wire[pos];if(!((marker>=0xa0&&marker<=0xbf)||(marker>=0xd9&&marker<=0xdb)))throw new Unsupported('JS object mapping requires string keys');if(/^(0|[1-9][0-9]*)$/.test(k))throw new Unsupported('JS numeric object key order is not a lossless map');r.push(...walk(k),...walk(v[k]));}return r;
  }
  throw Error('unexpected marker');
 }
 const r=walk(value);if(pos!==wire.length)throw Error('marker annotation consumption mismatch');return r;
}
for await(const line of createInterface({input:process.stdin,crlfDelay:Infinity})){
 try{
  const p=line.trim().split(/\s+/),op=p.shift();
  if(op==='E'){
   const state={floatKinds:new Set()},v=input(p,state);
   if(p.length)throw Error('extra tokens');
   if(state.floatKinds.size>1)throw new Unsupported('JS encoder float width option is global');
   const b=encode(v,{useBigInt64:true,extensionCodec:codec,forceFloat32:state.floatKinds.has('f'),forceIntegerToFloat:true});
   console.log('H '+hex(b));
  }else if(op==='D'){
   const b=unhex(p[0]),v=decode(b,{useBigInt64:true,extensionCodec:codec});
   console.log('V '+annotate(b,v).join(' '));
  }else throw Error('unknown operation');
 }catch(e){const knownKeyLimit=e.message.startsWith('The type of key must be string or number but ');console.log((e instanceof Unsupported||knownKeyLimit?'U ':'X ')+e.message.replaceAll('\n',' '));}
}
