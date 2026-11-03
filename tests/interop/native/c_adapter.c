/* Valid-input conformance adapter. Transport tokens are emitted by common.py. */
#define _POSIX_C_SOURCE 200809L
#include <msgpack.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *cursor;
static char *next(void) {
    char *r = strtok_r(NULL, " \r\n", &cursor);
    if (!r) { fputs("missing transport token\n", stderr); exit(2); }
    return r;
}
static unsigned char *unhex(const char *s, size_t *n) {
    *n = strcmp(s, "-") ? strlen(s)/2 : 0;
    unsigned char *r = malloc(*n ? *n : 1);
    if (!r) exit(2);
    for (size_t i=0;i<*n;i++) { unsigned v; if(sscanf(s+i*2,"%2x",&v)!=1) exit(2); r[i]=(unsigned char)v; }
    return r;
}
static void hexout(const void *data,size_t n) {
    const unsigned char *p=data;
    if(!n) putchar('-');
    for(size_t i=0;i<n;i++) printf("%02x",p[i]);
}
static void checked(int code) { if(code) {fputs("packing failed\n",stderr);exit(2);} }
static void pack(msgpack_packer *p) {
    char t=next()[0];
    switch(t) {
    case 'n': checked(msgpack_pack_nil(p));break;
    case 'b': checked(!strcmp(next(),"1")?msgpack_pack_true(p):msgpack_pack_false(p));break;
    case 'i': {char *s=next();checked(s[0]=='-'?msgpack_pack_int64(p,strtoll(s,NULL,10)):msgpack_pack_uint64(p,strtoull(s,NULL,10)));break;}
    case 'f': {uint32_t bits=(uint32_t)strtoul(next(),NULL,16);float f;memcpy(&f,&bits,4);checked(msgpack_pack_float(p,f));break;}
    case 'd': {uint64_t bits=strtoull(next(),NULL,16);double d;memcpy(&d,&bits,8);checked(msgpack_pack_double(p,d));break;}
    case 's': case 'x': {size_t n;unsigned char *b=unhex(next(),&n);if(t=='s'){checked(msgpack_pack_str(p,n));checked(msgpack_pack_str_body(p,b,n));}else{checked(msgpack_pack_bin(p,n));checked(msgpack_pack_bin_body(p,b,n));}free(b);break;}
    case 'a': case 'm': {size_t n=strtoull(next(),NULL,10);checked(t=='a'?msgpack_pack_array(p,n):msgpack_pack_map(p,n));for(size_t i=0;i<n*(t=='m'?2:1);i++)pack(p);break;}
    case 'e': {int8_t tag=(int8_t)strtol(next(),NULL,10);size_t n;unsigned char *b=unhex(next(),&n);
        if(tag==-1){msgpack_object o={.type=MSGPACK_OBJECT_EXT};o.via.ext.type=tag;o.via.ext.ptr=(const char*)b;o.via.ext.size=(uint32_t)n;msgpack_timestamp ts;if(!msgpack_object_to_timestamp(&o,&ts))exit(2);checked(msgpack_pack_timestamp(p,&ts));}
        else{checked(msgpack_pack_ext(p,n,tag));checked(msgpack_pack_ext_body(p,b,n));}free(b);break;}
    default: fputs("unknown token\n",stderr);exit(2);
    }
}
static void show(msgpack_object o) {
    switch(o.type) {
    case MSGPACK_OBJECT_NIL:printf("n ");break;
    case MSGPACK_OBJECT_BOOLEAN:printf("b %d ",o.via.boolean?1:0);break;
    case MSGPACK_OBJECT_POSITIVE_INTEGER:printf("i %" PRIu64 " ",o.via.u64);break;
    case MSGPACK_OBJECT_NEGATIVE_INTEGER:printf("i %" PRId64 " ",o.via.i64);break;
    case MSGPACK_OBJECT_FLOAT32:{float f=(float)o.via.f64;uint32_t bits;memcpy(&bits,&f,4);printf("f %08" PRIx32 " ",bits);break;}
    case MSGPACK_OBJECT_FLOAT64:{uint64_t bits;memcpy(&bits,&o.via.f64,8);printf("d %016" PRIx64 " ",bits);break;}
    case MSGPACK_OBJECT_STR:printf("s ");hexout(o.via.str.ptr,o.via.str.size);putchar(' ');break;
    case MSGPACK_OBJECT_BIN:printf("x ");hexout(o.via.bin.ptr,o.via.bin.size);putchar(' ');break;
    case MSGPACK_OBJECT_EXT:printf("e %d ",(int)o.via.ext.type);hexout(o.via.ext.ptr,o.via.ext.size);putchar(' ');break;
    case MSGPACK_OBJECT_ARRAY:printf("a %u ",o.via.array.size);for(uint32_t i=0;i<o.via.array.size;i++)show(o.via.array.ptr[i]);break;
    case MSGPACK_OBJECT_MAP:printf("m %u ",o.via.map.size);for(uint32_t i=0;i<o.via.map.size;i++){show(o.via.map.ptr[i].key);show(o.via.map.ptr[i].val);}break;
    default:exit(2);
    }
}
int main(void){
    char *line=NULL;size_t cap=0;
    while(getline(&line,&cap,stdin)>=0){
        char *op=strtok_r(line," \r\n",&cursor);if(!op)continue;
        if(!strcmp(op,"E")){
            msgpack_sbuffer b;msgpack_sbuffer_init(&b);msgpack_packer p;msgpack_packer_init(&p,&b,msgpack_sbuffer_write);pack(&p);
            printf("H ");hexout(b.data,b.size);putchar('\n');msgpack_sbuffer_destroy(&b);
        }else if(!strcmp(op,"D")){
            size_t n,off=0;unsigned char *b=unhex(next(),&n);msgpack_unpacked u;msgpack_unpacked_init(&u);
            msgpack_unpack_return ret=msgpack_unpack_next(&u,(const char*)b,n,&off);
            if(ret!=MSGPACK_UNPACK_SUCCESS || off!=n)printf("X unpack status=%d consumed=%zu/%zu\n",ret,off,n);
            else{printf("V ");show(u.data);putchar('\n');}
            msgpack_unpacked_destroy(&u);free(b);
        }else puts("X unknown operation");
        fflush(stdout);
    }free(line);return 0;
}
