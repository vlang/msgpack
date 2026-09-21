use std::io::{self,BufRead,Write,Cursor};
use rmpv::Value;
fn unhex(s:&str)->Result<Vec<u8>,String>{if s=="-"{return Ok(vec![])};(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).map_err(|e|e.to_string())).collect()}
fn hex(b:&[u8])->String{if b.is_empty(){return "-".into()};b.iter().map(|n|format!("{n:02x}")).collect()}
fn next<'a>(p:&mut impl Iterator<Item=&'a str>)->Result<&'a str,String>{p.next().ok_or("missing token".into())}
fn input<'a>(p:&mut impl Iterator<Item=&'a str>)->Result<Value,String>{Ok(match next(p)?{
 "n"=>Value::Nil,
 "b"=>Value::Boolean(next(p)?=="1"),
 "i"=>{let n=next(p)?;if n.starts_with('-'){Value::from(n.parse::<i64>().map_err(|e|e.to_string())?)}else{Value::from(n.parse::<u64>().map_err(|e|e.to_string())?)}},
 "f"=>Value::F32(f32::from_bits(u32::from_str_radix(next(p)?,16).map_err(|e|e.to_string())?)),
 "d"=>Value::F64(f64::from_bits(u64::from_str_radix(next(p)?,16).map_err(|e|e.to_string())?)),
 "s"=>Value::from(String::from_utf8(unhex(next(p)?)?).map_err(|e|e.to_string())?),
 "x"=>Value::Binary(unhex(next(p)?)?),
 "a"=>{let n:usize=next(p)?.parse().map_err(|_|"array count")?;Value::Array((0..n).map(|_|input(p)).collect::<Result<_,_>>()?)},
 "m"=>{let n:usize=next(p)?.parse().map_err(|_|"map count")?;Value::Map((0..n).map(|_|Ok((input(p)?,input(p)?))).collect::<Result<_,String>>()?)},
 "e"=>{let n:i8=next(p)?.parse().map_err(|_|"ext type")?;Value::Ext(n,unhex(next(p)?)?)},
 _=>return Err("unknown token".into())})}
fn output(v:&Value,o:&mut Vec<String>){match v{
 Value::Nil=>o.push("n".into()),
 Value::Boolean(b)=>o.extend(["b".into(),if *b{"1"}else{"0"}.into()]),
 Value::Integer(i)=>o.extend(["i".into(),i.to_string()]),
 Value::F32(f)=>o.extend(["f".into(),format!("{:08x}",f.to_bits())]),
 Value::F64(f)=>o.extend(["d".into(),format!("{:016x}",f.to_bits())]),
 Value::String(s)=>o.extend(["s".into(),hex(s.as_bytes())]),
 Value::Binary(b)=>o.extend(["x".into(),hex(b)]),
 Value::Array(a)=>{o.extend(["a".into(),a.len().to_string()]);for x in a{output(x,o)}},
 Value::Map(m)=>{o.extend(["m".into(),m.len().to_string()]);for(k,v)in m{output(k,o);output(v,o)}},
 Value::Ext(t,b)=>o.extend(["e".into(),t.to_string(),hex(b)])}}
fn run(line:&str)->Result<String,String>{let mut p=line.split_whitespace();match next(&mut p)?{
 "E"=>{let v=input(&mut p)?;if p.next().is_some(){return Err("trailing tokens".into())};let mut b=vec![];rmpv::encode::write_value(&mut b,&v).map_err(|e|e.to_string())?;Ok(format!("H {}",hex(&b)))},
 "D"=>{let b=unhex(next(&mut p)?)?;let mut r=Cursor::new(&b);let v=rmpv::decode::read_value(&mut r).map_err(|e|e.to_string())?;if r.position()!=b.len() as u64{return Err("trailing bytes".into())};let mut o=vec![];output(&v,&mut o);Ok(format!("V {}",o.join(" ")))},
 _=>Err("unknown operation".into())}}
fn main(){for line in io::stdin().lock().lines(){let r=run(&line.unwrap());println!("{}",r.unwrap_or_else(|e|format!("X {}",e.replace('\n'," "))));io::stdout().flush().unwrap()}}
