#!/usr/bin/env perl

# ====================================================================
# Written by Andy Polyakov <appro@fy.chalmers.se> for the OpenSSL
# project. The module is, however, dual licensed under OpenSSL and
# CRYPTOGAMS licenses depending on where you obtain it. For further
# details see http://www.openssl.org/~appro/cryptogams/.
# ====================================================================
#
# This module implements support for Intel AES-NI extension. In
# OpenSSL context it's used with Intel engine, but can also be used as
# drop-in replacement for crypto/aes/asm/aes-586.pl [see below for
# details].
#
# Performance.
#
# To start with see corresponding paragraph in aesni-x86_64.pl...
# Instead of filling table similar to one found there I've chosen to
# summarize *comparison* results for raw ECB, CTR and CBC benchmarks.
# The simplified table below represents 32-bit performance relative
# to 64-bit one in every given point. Ratios vary for different
# encryption modes, therefore interval values.
#
#	16-byte     64-byte     256-byte    1-KB        8-KB
#	53-67%      67-84%      91-94%      95-98%      97-99.5%
#
# Lower ratios for smaller block sizes are perfectly understandable,
# because function call overhead is higher in 32-bit mode. Largest
# 8-KB block performance is virtually same: 32-bit code is less than
# 1% slower for ECB, CBC and CCM, and ~3% slower otherwise. 

$PREFIX="aesni";	# if $PREFIX is set to "AES", the script
			# generates drop-in replacement for
			# crypto/aes/asm/aes-586.pl:-)
$inline=1;		# inline _aesni_[en|de]crypt

$0 =~ m/(.*[\/\\])[^\/\\]+$/; $dir=$1;
push(@INC,"${dir}","${dir}../../perlasm");
require "x86asm.pl";

&asm_init($ARGV[0],$0);

if ($PREFIX eq "aesni")	{ $movekey=*movaps; }
else			{ $movekey=*movups; }

$len="eax";
$rounds="ecx";
$key="edx";
$inp="esi";
$out="edi";
$rounds_="ebx";	# backup copy for $rounds
$key_="ebp";	# backup copy for $key

$inout0="xmm0";
$inout1="xmm1";
$inout2="xmm2";
$rndkey0="xmm3";
$rndkey1="xmm4";
$ivec="xmm5";
$in0="xmm6";
$in1="xmm7";	$inout3="xmm7";

# AESNI extenstion
sub aeskeygenassist
{ my($dst,$src,$imm)=@_;
    if ("$dst:$src" =~ /xmm([0-7]):xmm([0-7])/)
    {	&data_byte(0x66,0x0f,0x3a,0xdf,0xc0|($1<<3)|$2,$imm);	}
}
sub aescommon
{ my($opcodelet,$dst,$src)=@_;
    if ("$dst:$src" =~ /xmm([0-7]):xmm([0-7])/)
    {	&data_byte(0x66,0x0f,0x38,$opcodelet,0xc0|($1<<3)|$2);}
}
sub aesimc	{ aescommon(0xdb,@_); }
sub aesenc	{ aescommon(0xdc,@_); }
sub aesenclast	{ aescommon(0xdd,@_); }
sub aesdec	{ aescommon(0xde,@_); }
sub aesdeclast	{ aescommon(0xdf,@_); }

# Inline version of internal aesni_[en|de]crypt1
{ my $sn;
sub aesni_inline_generate1
{ my ($p,$inout)=@_; $inout=$inout0 if (!defined($inout));
  $sn++;

    &movdqu		($rndkey0,&QWP(0,$key));
    &$movekey		($rndkey1,&QWP(16,$key));
    &lea		($key,&DWP(32,$key));
    &pxor		($inout,$rndkey0);
    &set_label("${p}1_loop_$sn");
	eval"&aes${p}	($inout,$rndkey1)";
	&dec		($rounds);
	&$movekey	($rndkey1,&QWP(0,$key));
	&lea		($key,&DWP(16,$key));
    &jnz		(&label("${p}1_loop_$sn"));
    eval"&aes${p}last	($inout,$rndkey1)";
}}

sub aesni_generate1	# fully unrolled loop
{ my ($p,$inout)=@_; $inout=$inout0 if (!defined($inout));

    &function_begin_B("_aesni_${p}rypt1");
	&movdqu		($rndkey0,&QWP(0,$key));
	&$movekey	($rndkey1,&QWP(0x10,$key));
	&pxor		($inout,$rndkey0);
	&$movekey	($rndkey0,&QWP(0x20,$key));
	&lea		($key,&DWP(0x30,$key));
	&cmp		($rounds,11);
	&jb		(&label("${p}128"));
	&lea		($key,&DWP(0x20,$key));
	&je		(&label("${p}192"));
	&lea		($key,&DWP(0x20,$key));
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(-0x40,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(-0x30,$key));
    &set_label("${p}192");
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(-0x20,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(-0x10,$key));
    &set_label("${p}128");
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(0,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0x10,$key));
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(0x20,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0x30,$key));
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(0x40,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0x50,$key));
	eval"&aes${p}	($inout,$rndkey1)";
	&$movekey	($rndkey1,&QWP(0x60,$key));
	eval"&aes${p}	($inout,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0x70,$key));
	eval"&aes${p}	($inout,$rndkey1)";
    eval"&aes${p}last	($inout,$rndkey0)";
    &ret();
    &function_end_B("_aesni_${p}rypt1");
}

# void $PREFIX_encrypt (const void *inp,void *out,const AES_KEY *key);
&aesni_generate1("enc") if (!$inline);
&function_begin_B("${PREFIX}_encrypt");
	&mov	("eax",&wparam(0));
	&mov	($key,&wparam(2));
	&movdqu	($inout0,&QWP(0,"eax"));
	&mov	($rounds,&DWP(240,$key));
	&mov	("eax",&wparam(1));
	if ($inline)
	{   &aesni_inline_generate1("enc");	}
	else
	{   &call	("_aesni_encrypt1");	}
	&movups	(&QWP(0,"eax"),$inout0);
	&ret	();
&function_end_B("${PREFIX}_encrypt");

# void $PREFIX_decrypt (const void *inp,void *out,const AES_KEY *key);
&aesni_generate1("dec") if(!$inline);
&function_begin_B("${PREFIX}_decrypt");
	&mov	("eax",&wparam(0));
	&mov	($key,&wparam(2));
	&movdqu	($inout0,&QWP(0,"eax"));
	&mov	($rounds,&DWP(240,$key));
	&mov	("eax",&wparam(1));
	if ($inline)
	{   &aesni_inline_generate1("dec");	}
	else
	{   &call	("_aesni_decrypt1");	}
	&movups	(&QWP(0,"eax"),$inout0);
	&ret	();
&function_end_B("${PREFIX}_decrypt");

# _aesni_[en|de]crypt[34] are private interfaces, N denotes interleave
# factor. Why 3x subroutine is used in loops? Even though aes[enc|dec]
# latency is 6, it turned out that it can be scheduled only every
# *second* cycle. Thus 3x interleave is the one providing optimal
# utilization, i.e. when subroutine's throughput is virtually same as
# of non-interleaved subroutine [for number of input blocks up to 3].
# This is why it makes no sense to implement 2x subroutine. As soon
# as/if Intel improves throughput by making it possible to schedule
# the instructions in question *every* cycles I would have to
# implement 6x interleave and use it in loop...
sub aesni_generate3
{ my $p=shift;

    &function_begin_B("_aesni_${p}rypt3");
	&$movekey	($rndkey0,&QWP(0,$key));
	&shr		($rounds,1);
	&$movekey	($rndkey1,&QWP(16,$key));
	&lea		($key,&DWP(32,$key));
	&pxor		($inout0,$rndkey0);
	&pxor		($inout1,$rndkey0);
	&pxor		($inout2,$rndkey0);
	&$movekey	($rndkey0,&QWP(0,$key));

    &set_label("${p}3_loop");
	eval"&aes${p}	($inout0,$rndkey1)";
	eval"&aes${p}	($inout1,$rndkey1)";
	&dec		($rounds);
	eval"&aes${p}	($inout2,$rndkey1)";
	&$movekey	($rndkey1,&QWP(16,$key));
	eval"&aes${p}	($inout0,$rndkey0)";
	eval"&aes${p}	($inout1,$rndkey0)";
	&lea		($key,&DWP(32,$key));
	eval"&aes${p}	($inout2,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0,$key));
	&jnz		(&label("${p}3_loop"));
    eval"&aes${p}	($inout0,$rndkey1)";
    eval"&aes${p}	($inout1,$rndkey1)";
    eval"&aes${p}	($inout2,$rndkey1)";
    eval"&aes${p}last	($inout0,$rndkey0)";
    eval"&aes${p}last	($inout1,$rndkey0)";
    eval"&aes${p}last	($inout2,$rndkey0)";
    &ret();
    &function_end_B("_aesni_${p}rypt3");
}

# 4x interleave is implemented to improve small block performance,
# most notably [and naturally] 4 block by ~30%. One can argue that one
# should have implemented 5x as well, but improvement  would be <20%,
# so it's not worth it...
sub aesni_generate4
{ my $p=shift;

    &function_begin_B("_aesni_${p}rypt4");
	&$movekey	($rndkey0,&QWP(0,$key));
	&$movekey	($rndkey1,&QWP(16,$key));
	&shr		($rounds,1);
	&lea		($key,&DWP(32,$key));
	&pxor		($inout0,$rndkey0);
	&pxor		($inout1,$rndkey0);
	&pxor		($inout2,$rndkey0);
	&pxor		($inout3,$rndkey0);
	&$movekey	($rndkey0,&QWP(0,$key));

    &set_label("${p}3_loop");
	eval"&aes${p}	($inout0,$rndkey1)";
	eval"&aes${p}	($inout1,$rndkey1)";
	&dec		($rounds);
	eval"&aes${p}	($inout2,$rndkey1)";
	eval"&aes${p}	($inout3,$rndkey1)";
	&$movekey	($rndkey1,&QWP(16,$key));
	eval"&aes${p}	($inout0,$rndkey0)";
	eval"&aes${p}	($inout1,$rndkey0)";
	&lea		($key,&DWP(32,$key));
	eval"&aes${p}	($inout2,$rndkey0)";
	eval"&aes${p}	($inout3,$rndkey0)";
	&$movekey	($rndkey0,&QWP(0,$key));
    &jnz		(&label("${p}3_loop"));

    eval"&aes${p}	($inout0,$rndkey1)";
    eval"&aes${p}	($inout1,$rndkey1)";
    eval"&aes${p}	($inout2,$rndkey1)";
    eval"&aes${p}	($inout3,$rndkey1)";
    eval"&aes${p}last	($inout0,$rndkey0)";
    eval"&aes${p}last	($inout1,$rndkey0)";
    eval"&aes${p}last	($inout2,$rndkey0)";
    eval"&aes${p}last	($inout3,$rndkey0)";
    &ret();
    &function_end_B("_aesni_${p}rypt4");
}
&aesni_generate3("enc") if ($PREFIX eq "aesni");
&aesni_generate3("dec");
&aesni_generate4("enc") if ($PREFIX eq "aesni");
&aesni_generate4("dec");

if ($PREFIX eq "aesni") {
######################################################################
# void aesni_ecb_encrypt (const void *in, void *out,
#                         size_t length, const AES_KEY *key,
#                         int enc);
&function_begin("aesni_ecb_encrypt");
	&mov	($inp,&wparam(0));
	&mov	($out,&wparam(1));
	&mov	($len,&wparam(2));
	&mov	($key,&wparam(3));
	&mov	($rounds,&wparam(4));
	&cmp	($len,16);
	&jb	(&label("ecb_ret"));
	&and	($len,-16);
	&test	($rounds,$rounds)
	&mov	($rounds,&DWP(240,$key));
	&mov	($key_,$key);		# backup $key
	&mov	($rounds_,$rounds);	# backup $rounds
	&jz	(&label("ecb_decrypt"));

	&cmp	($len,0x40);
	&jbe	(&label("ecb_enc_tail"));
	&sub	($len,0x40);
	&jmp	(&label("ecb_enc_loop3"));

&set_label("ecb_enc_loop3",16);
	&movups	($inout0,&QWP(0,$inp));
	&movups	($inout1,&QWP(0x10,$inp));
	&movups	($inout2,&QWP(0x20,$inp));
	&call	("_aesni_encrypt3");
	&lea	($inp,&DWP(0x30,$inp));
	&movups	(&QWP(0,$out),$inout0);
	&mov	($key,$key_);		# restore $key
	&movups	(&QWP(0x10,$out),$inout1);
	&mov	($rounds,$rounds_);	# restore $rounds
	&movups	(&QWP(0x20,$out),$inout2);
	&lea	($out,&DWP(0x30,$out));
	&sub	($len,0x30);
	&ja	(&label("ecb_enc_loop3"));

	&add	($len,0x40);
&set_label("ecb_enc_tail");
	&movups	($inout0,&QWP(0,$inp));
	&cmp	($len,0x20);
	&jb	(&label("ecb_enc_one"));
	&movups	($inout1,&QWP(0x10,$inp));
	&je	(&label("ecb_enc_two"));
	&movups	($inout2,&QWP(0x20,$inp));
	&cmp	($len,0x30);
	&je	(&label("ecb_enc_three"));
	&movups	($inout3,&QWP(0x30,$inp));
	&call	("_aesni_encrypt4");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&movups	(&QWP(0x20,$out),$inout2);
	&movups	(&QWP(0x30,$out),$inout3);
	jmp	(&label("ecb_ret"));

&set_label("ecb_enc_one",16);
	if ($inline)
	{   &aesni_inline_generate1("enc");	}
	else
	{   &call	("_aesni_encrypt1");	}
	&movups	(&QWP(0,$out),$inout0);
	&jmp	(&label("ecb_ret"));

&set_label("ecb_enc_two",16);
	&pxor	($inout2,$inout2);
	&call	("_aesni_encrypt3");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&jmp	(&label("ecb_ret"));

&set_label("ecb_enc_three",16);
	&call	("_aesni_encrypt3");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&movups	(&QWP(0x20,$out),$inout2);
	&jmp	(&label("ecb_ret"));
######################################################################
&set_label("ecb_decrypt",16);
	&cmp	($len,0x40);
	&jbe	(&label("ecb_dec_tail"));
	&sub	($len,0x40);
	&jmp	(&label("ecb_dec_loop3"));

&set_label("ecb_dec_loop3",16);
	&movups	($inout0,&QWP(0,$inp));
	&movups	($inout1,&QWP(0x10,$inp));
	&movups	($inout2,&QWP(0x20,$inp));
	&call	("_aesni_decrypt3");
	&lea	($inp,&DWP(0x30,$inp));
	&movups	(&QWP(0,$out),$inout0);
	&mov	($key,$key_);		# restore $key
	&movups	(&QWP(0x10,$out),$inout1);
	&mov	($rounds,$rounds_);	# restore $rounds
	&movups	(&QWP(0x20,$out),$inout2);
	&lea	($out,&DWP(0x30,$out));
	&sub	($len,0x30);
	&ja	(&label("ecb_dec_loop3"));

	&add	($len,0x40);
&set_label("ecb_dec_tail");
	&movups	($inout0,&QWP(0,$inp));
	&cmp	($len,0x20);
	&jb	(&label("ecb_dec_one"));
	&movups	($inout1,&QWP(0x10,$inp));
	&je	(&label("ecb_dec_two"));
	&movups	($inout2,&QWP(0x20,$inp));
	&cmp	($len,0x30);
	&je	(&label("ecb_dec_three"));
	&movups	($inout3,&QWP(0x30,$inp));
	&call	("_aesni_decrypt4");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&movups	(&QWP(0x20,$out),$inout2);
	&movups	(&QWP(0x30,$out),$inout3);
	&jmp	(&label("ecb_ret"));

&set_label("ecb_dec_one",16);
	if ($inline)
	{   &aesni_inline_generate1("dec");	}
	else
	{   &call	("_aesni_decrypt1");	}
	&movups	(&QWP(0,$out),$inout0);
	&jmp	(&label("ecb_ret"));

&set_label("ecb_dec_two",16);
	&pxor	($inout2,$inout2);
	&call	("_aesni_decrypt3");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&jmp	(&label("ecb_ret"));

&set_label("ecb_dec_three",16);
	&call	("_aesni_decrypt3");
	&movups	(&QWP(0,$out),$inout0);
	&movups	(&QWP(0x10,$out),$inout1);
	&movups	(&QWP(0x20,$out),$inout2);

&set_label("ecb_ret");
&function_end("aesni_ecb_encrypt");

######################################################################
# void aesni_ccm64_[en|de]crypt_blocks (const void *in, void *out,
#                         size_t blocks, const AES_KEY *key,
#                         const char *ivec,char *cmac);
#
# Handles only complete blocks, operates on 64-bit counter and
# does not update *ivec! Nor does it finalize CMAC value
# (see engine/eng_aesni.c for details)
#
&function_begin("aesni_ccm64_encrypt_blocks");
	&mov	($inp,&wparam(0));
	&mov	($out,&wparam(1));
	&mov	($len,&wparam(2));
	&mov	($key,&wparam(3));
	&mov	($rounds_,&wparam(4));
	&mov	($rounds,&wparam(5));
	&mov	($key_,"esp");
	&sub	("esp",60);
	&and	("esp",-16);			# align stack
	&mov	(&DWP(48,"esp"),$key_);

	&movdqu	($ivec,&QWP(0,$rounds_));	# load ivec
	&movdqu	($inout1,&QWP(0,$rounds));	# load cmac

	# compose byte-swap control mask for pshufb on stack
	&mov	(&DWP(0,"esp"),0x0c0d0e0f);
	&mov	(&DWP(4,"esp"),0x08090a0b);
	&mov	(&DWP(8,"esp"),0x04050607);
	&mov	(&DWP(12,"esp"),0x00010203);

	# compose counter increment vector on stack
	&mov	($rounds,1);
	&xor	($key_,$key_);
	&mov	(&DWP(16,"esp"),$rounds);
	&mov	(&DWP(20,"esp"),$key_);
	&mov	(&DWP(24,"esp"),$key_);
	&mov	(&DWP(28,"esp"),$key_);

	&movdqa	($inout3,&QWP(0,"esp"));
	&pshufb	($ivec,$inout3);		# keep iv in reverse order

	&mov	($rounds,&DWP(240,$key));
	&mov	($key_,$key);
	&mov	($rounds_,$rounds);
	&movdqa	($inout0,$ivec);

&set_label("ccm64_enc_outer");
	&movdqu	($in0,&QWP(0,$inp));
	&pshufb	($inout0,$inout3);
	&mov	($key,$key_);
	&mov	($rounds,$rounds_);
	&pxor	($inout1,$in0);			# cmac^=inp
	&pxor	($inout2,$inout2);

	&call	("_aesni_encrypt3");

	&paddq	($ivec,&QWP(16,"esp"));
	&dec	($len);
	&lea	($inp,&DWP(16,$inp));
	&pxor	($in0,$inout0);			# inp^=E(ivec)
	&movdqa	($inout0,$ivec);
	&movdqu	(&QWP(0,$out),$in0);
	&lea	($out,&DWP(16,$out));
	&jnz	(&label("ccm64_enc_outer"));

	&mov	("esp",&DWP(48,"esp"));
	&mov	($out,&wparam(5));
	&movdqu	(&QWP(0,$out),$inout1);
&function_end("aesni_ccm64_encrypt_blocks");

&function_begin("aesni_ccm64_decrypt_blocks");
	&mov	($inp,&wparam(0));
	&mov	($out,&wparam(1));
	&mov	($len,&wparam(2));
	&mov	($key,&wparam(3));
	&mov	($rounds_,&wparam(4));
	&mov	($rounds,&wparam(5));
	&mov	($key_,"esp");
	&sub	("esp",60);
	&and	("esp",-16);			# align stack
	&mov	(&DWP(48,"esp"),$key_);

	&movdqu	($ivec,&QWP(0,$rounds_));	# load ivec
	&movdqu	($inout1,&QWP(0,$rounds));	# load cmac

	# compose byte-swap control mask for pshufb on stack
	&mov	(&DWP(0,"esp"),0x0c0d0e0f);
	&mov	(&DWP(4,"esp"),0x08090a0b);
	&mov	(&DWP(8,"esp"),0x04050607);
	&mov	(&DWP(12,"esp"),0x00010203);

	# compose counter increment vector on stack
	&mov	($rounds,1);
	&xor	($key_,$key_);
	&mov	(&DWP(16,"esp"),$rounds);
	&mov	(&DWP(20,"esp"),$key_);
	&mov	(&DWP(24,"esp"),$key_);
	&mov	(&DWP(28,"esp"),$key_);

	&movdqa	($inout3,&QWP(0,"esp"));	# bswap mask
	&movdqa	($inout0,$ivec);
	&pshufb	($ivec,$inout3);		# keep iv in reverse order

	&mov	($rounds,&DWP(240,$key));
	&mov	($key_,$key);
	&mov	($rounds_,$rounds);

	if ($inline)
	{   &aesni_inline_generate1("enc");	}
	else
	{   &call	("_aesni_encrypt1");	}

&set_label("ccm64_dec_outer");
	&movdqu	($in0,&QWP(0,$inp));
	&paddq	($ivec,&QWP(16,"esp"));
	&dec	($len);
	&lea	($inp,&QWP(16,$inp));
	&pxor	($in0,$inout0);
	&movdqa	($inout0,$ivec);
	&mov	($key,$key_);
	&mov	($rounds,$rounds_);
	&pshufb	($inout0,$inout3);
	&movdqu	(&QWP(0,$out),$in0);
	&lea	($out,&DWP(16,$out));

	&jz	(&label("ccm64_dec_break"));

	&pxor	($inout2,$inout2);
	&call	("_aesni_encrypt3");

	&jmp	(&label("ccm64_dec_outer"));

&set_label("ccm64_dec_break",16);
	if ($inline)
	{   &aesni_inline_generate1("enc",$inout1);	}
	else
	{   &call	("_aesni_encrypt1",$inout1);	}

	&mov	("esp",&DWP(48,"esp"));
	&mov	($out,&wparam(5));
	&movdqu	(&QWP(0,$out),$inout1);
&function_end("aesni_ccm64_decrypt_blocks");

######################################################################
# void aesni_ctr32_encrypt_blocks (const void *in, void *out,
#                         size_t blocks, const AES_KEY *key,
#                         const char *ivec);
#
# Handles only complete blocks, operates on 32-bit counter and
# does not update *ivec! (see engine/eng_aesni.c for details)
#
&function_begin("aesni_ctr32_encrypt_blocks");
	&mov	($inp,&wparam(0));
	&mov	($out,&wparam(1));
	&mov	($len,&wparam(2));
	&mov	($key,&wparam(3));
	&mov	($rounds_,&wparam(4));
	&mov	($key_,"esp");
	&sub	("esp",60);
	&and	("esp",-16);			# align stack
	&mov	(&DWP(48,"esp"),$key_);

	&cmp	($len,1);
	&je	(&label("ctr32_one_shortcut"));

	&movups	($inout3,&QWP(0,$rounds_));	# load ivec

	# compose byte-swap control mask for pshufb on stack
	&mov	(&DWP(0,"esp"),0x0c0d0e0f);
	&mov	(&DWP(4,"esp"),0x08090a0b);
	&mov	(&DWP(8,"esp"),0x04050607);
	&mov	(&DWP(12,"esp"),0x00010203);

	# compose counter increment vector on stack
	&mov	($rounds,3);
	&xor	($key_,$key_);
	&mov	(&DWP(16,"esp"),$rounds);
	&mov	(&DWP(20,"esp"),$rounds);
	&mov	(&DWP(24,"esp"),$rounds);
	&mov	(&DWP(28,"esp"),$key_);

	&pextrd	($rounds_,$inout3,3);		# pull 32-bit counter
	&pinsrd	($inout3,$key_,3);		# wipe 32-bit counter

	&mov	($rounds,&DWP(240,$key));	# key->rounds
	&movdqa	($rndkey0,&QWP(0,"esp"));	# load byte-swap mask

	# $ivec is vector of 3 32-bit counters
	&pxor	($ivec,$ivec);
	&bswap	($rounds_);
	&pinsrd	($ivec,$rounds_,0);
	&inc	($rounds_);
	&pinsrd	($ivec,$rounds_,1);
	&inc	($rounds_);
	&pinsrd	($ivec,$rounds_,2);
	&pshufb	($ivec,$rndkey0);		# byte swap

	&cmp	($len,4);
	&jbe	(&label("ctr32_tail"));
	&movdqa	(&QWP(32,"esp"),$inout3);	# save counter-less ivec
	&mov	($rounds_,$rounds);
	&mov	($key_,$key);
	&sub	($len,4);
	&jmp	(&label("ctr32_loop3"));

&set_label("ctr32_loop3",16);
	&pshufd	($inout0,$ivec,3<<6);		# place counter to upper dword
	&pshufd	($inout1,$ivec,2<<6);
	&por	($inout0,$inout3);		# merge counter-less ivec
	&pshufd	($inout2,$ivec,1<<6);
	&por	($inout1,$inout3);
	&por	($inout2,$inout3);

	# inline _aesni_encrypt3 and interleave last round
	# with own code...

	&$movekey	($rndkey0,&QWP(0,$key));
	&shr		($rounds,1);
	&$movekey	($rndkey1,&QWP(16,$key));
	&lea		($key,&DWP(32,$key));
	&pxor		($inout0,$rndkey0);
	&pxor		($inout1,$rndkey0);
	&pxor		($inout2,$rndkey0);
	&$movekey	($rndkey0,&QWP(0,$key));

&set_label("ctr32_enc_loop3");
	&aesenc		($inout0,$rndkey1);
	&aesenc		($inout1,$rndkey1);
	&dec		($rounds);
	&aesenc		($inout2,$rndkey1);
	&$movekey	($rndkey1,&QWP(16,$key));
	&aesenc		($inout0,$rndkey0);
	&aesenc		($inout1,$rndkey0);
	&lea		($key,&DWP(32,$key));
	&aesenc		($inout2,$rndkey0);
	&$movekey	($rndkey0,&QWP(0,$key));
	&jnz		(&label("ctr32_enc_loop3"));

	&aesenc		($inout0,$rndkey1);
	&aesenc		($inout1,$rndkey1);
	&aesenc		($inout2,$rndkey1);
	&movdqa		($rndkey1,&QWP(0,"esp"));	# load byte-swap mask

	&aesenclast	($inout0,$rndkey0);
	&pshufb		($ivec,$rndkey1);		# byte swap
	&movdqu		($in0,&QWP(0,$inp));
	&aesenclast	($inout1,$rndkey0);
	&paddd		($ivec,&QWP(16,"esp"));		# counter increment
	&movdqu		($in1,&QWP(0x10,$inp));
	&aesenclast	($inout2,$rndkey0);
	&pshufb		($ivec,$rndkey1);		# byte swap
	&movdqu		($rndkey0,&QWP(0x20,$inp));
	&lea		($inp,&DWP(0x30,$inp));

	&pxor	($in0,$inout0);
	&mov	($key,$key_);
	&pxor	($in1,$inout1);
	&movdqu	(&QWP(0,$out),$in0);
	&pxor	($rndkey0,$inout2);
	&movdqu	(&QWP(0x10,$out),$in1);
	&movdqu	(&QWP(0x20,$out),$rndkey0);
	&movdqa	($inout3,&QWP(32,"esp"));	# load counter-less ivec

	&sub	($len,3);
	&lea	($out,&DWP(0x30,$out));
	&mov	($rounds,$rounds_);
	&ja	(&label("ctr32_loop3"));

	&pextrd	($rounds_,$ivec,1);		# might need last counter value
	&add	($len,4);
	&bswap	($rounds_);

&set_label("ctr32_tail");
	&pshufd	($inout0,$ivec,3<<6);
	&pshufd	($inout1,$ivec,2<<6);
	&por	($inout0,$inout3);
	&cmp	($len,2);
	&jb	(&label("ctr32_one"));
	&lea	($rounds_,&DWP(1,$rounds_));
	&pshufd	($inout2,$ivec,1<<6);
	&por	($inout1,$inout3);
	&je	(&label("ctr32_two"));
	&bswap	($rounds_);
	&por	($inout2,$inout3);
	&cmp	($len,3);
	&je	(&label("ctr32_three"));

	&pinsrd	($inout3,$rounds_,3);		# compose last counter value

	&call	("_aesni_encrypt4");

	&movdqu	($in0,&QWP(0,$inp));
	&movdqu	($rndkey1,&QWP(0x10,$inp));
	&pxor	($in0,$inout0);
	&movdqu	($rndkey0,&QWP(0x20,$inp));
	&pxor	($rndkey1,$inout1);
	&movdqu	($ivec,&QWP(0x30,$inp));
	&pxor	($rndkey0,$inout2);
	&movdqu	(&QWP(0,$out),$in0);
	&pxor	($ivec,$inout3);
	&movdqu	(&QWP(0x10,$out),$rndkey1);
	&movdqu	(&QWP(0x20,$out),$rndkey0);
	&movdqu	(&QWP(0x30,$out),$ivec);
	&jmp	(&label("ctr32_ret"));

&set_label("ctr32_one_shortcut",16);
	&movdqu	($inout0,&QWP(0,$rounds_));	# load ivec
	&mov	($rounds,&DWP(240,$key));
	
&set_label("ctr32_one");
	if ($inline)
	{   &aesni_inline_generate1("enc");	}
	else
	{   &call	("_aesni_encrypt1");	}
	&movdqu	($in0,&QWP(0,$inp));
	&pxor	($in0,$inout0);
	&movdqu	(&QWP(0,$out),$in0);
	&jmp	(&label("ctr32_ret"));

&set_label("ctr32_two",16);
	&pxor	($inout2,$inout2);
	&call	("_aesni_encrypt3");
	&movdqu	($in0,&QWP(0,$inp));
	&movdqu	($in1,&QWP(0x10,$inp));
	&pxor	($in0,$inout0);
	&pxor	($in1,$inout1);
	&movdqu	(&QWP(0,$out),$in0);
	&movdqu	(&QWP(0x10,$out),$in1);
	&jmp	(&label("ctr32_ret"));

&set_label("ctr32_three",16);
	&call	("_aesni_encrypt3");
	&movdqu	($in0,&QWP(0,$inp));
	&movdqu	($in1,&QWP(0x10,$inp));
	&movdqu	($rndkey1,&QWP(0x20,$inp));
	&pxor	($in0,$inout0);
	&pxor	($in1,$inout1);
	&movdqu	(&QWP(0,$out),$in0);
	&pxor	($rndkey1,$inout2);
	&movdqu	(&QWP(0x10,$out),$in1);
	&movdqu	(&QWP(0x20,$out),$rndkey1);

&set_label("ctr32_ret");
	&mov	("esp",&DWP(48,"esp"));
&function_end("aesni_ctr32_encrypt_blocks");
}

######################################################################
# void $PREFIX_cbc_encrypt (const void *inp, void *out,
#                           size_t length, const AES_KEY *key,
#                           unsigned char *ivp,const int enc);
&function_begin("${PREFIX}_cbc_encrypt");
	&mov	($inp,&wparam(0));
	&mov	($out,&wparam(1));
	&mov	($len,&wparam(2));
	&mov	($key,&wparam(3));
	&mov	($key_,&wparam(4));
	&test	($len,$len);
	&jz	(&label("cbc_ret"));

	&cmp	(&wparam(5),0);
	&movdqu	($ivec,&QWP(0,$key_));	# load IV
	&mov	($rounds,&DWP(240,$key));
	&mov	($key_,$key);		# backup $key
	&mov	($rounds_,$rounds);	# backup $rounds
	&je	(&label("cbc_decrypt"));

	&movdqa	($inout0,$ivec);
	&cmp	($len,16);
	&jb	(&label("cbc_enc_tail"));
	&sub	($len,16);
	&jmp	(&label("cbc_enc_loop"));

&set_label("cbc_enc_loop",16);
	&movdqu	($ivec,&QWP(0,$inp));
	&lea	($inp,&DWP(16,$inp));
	&pxor	($inout0,$ivec);
	if ($inline)
	{   &aesni_inline_generate1("enc");	}
	else
	{   &call	("_aesni_encrypt1");	}
	&mov	($rounds,$rounds_);	# restore $rounds
	&mov	($key,$key_);		# restore $key
	&movups	(&QWP(0,$out),$inout0);	# store output
	&lea	($out,&DWP(16,$out));
	&sub	($len,16);
	&jnc	(&label("cbc_enc_loop"));
	&add	($len,16);
	&jnz	(&label("cbc_enc_tail"));
	&movaps	($ivec,$inout0);
	&jmp	(&label("cbc_ret"));

&set_label("cbc_enc_tail");
	&mov	("ecx",$len);		# zaps $rounds
	&data_word(0xA4F3F689);		# rep movsb
	&mov	("ecx",16);		# zero tail
	&sub	("ecx",$len);
	&xor	("eax","eax");		# zaps $len
	&data_word(0xAAF3F689);		# rep stosb
	&lea	($out,&DWP(-16,$out));	# rewind $out by 1 block
	&mov	($rounds,$rounds_);	# restore $rounds
	&mov	($inp,$out);		# $inp and $out are the same
	&mov	($key,$key_);		# restore $key
	&jmp	(&label("cbc_enc_loop"));
######################################################################
&set_label("cbc_decrypt",16);
	&cmp	($len,0x40);
	&jbe	(&label("cbc_dec_tail"));
	&sub	($len,0x40);
	&jmp	(&label("cbc_dec_loop3"));

&set_label("cbc_dec_loop3",16);
	&movups	($inout0,&QWP(0,$inp));
	&movups	($inout1,&QWP(0x10,$inp));
	&movups	($inout2,&QWP(0x20,$inp));
	&movaps	($in0,$inout0);
	&movaps	($in1,$inout1);

	&call	("_aesni_decrypt3");

	&pxor	($inout0,$ivec);
	&pxor	($inout1,$in0);
	&movdqu	($ivec,&QWP(0x20,$inp));
	&lea	($inp,&DWP(0x30,$inp));
	&pxor	($inout2,$in1);
	&movdqu	(&QWP(0,$out),$inout0);
	&mov	($rounds,$rounds_)	# restore $rounds
	&movdqu	(&QWP(0x10,$out),$inout1);
	&mov	($key,$key_);		# restore $key
	&movdqu	(&QWP(0x20,$out),$inout2);
	&lea	($out,&DWP(0x30,$out));
	&sub	($len,0x30);
	&ja	(&label("cbc_dec_loop3"));

	&add	($len,0x40);
&set_label("cbc_dec_tail");
	&movups	($inout0,&QWP(0,$inp));
	&movaps	($in0,$inout0);
	&cmp	($len,0x10);
	&jbe	(&label("cbc_dec_one"));
	&movups	($inout1,&QWP(0x10,$inp));
	&movaps	($in1,$inout1);
	&cmp	($len,0x20);
	&jbe	(&label("cbc_dec_two"));
	&movups	($inout2,&QWP(0x20,$inp));
	&cmp	($len,0x30);
	&jbe	(&label("cbc_dec_three"));
	&movups	($inout3,&QWP(0x30,$inp));
	&call	("_aesni_decrypt4");
	&movdqu	($rndkey0,&QWP(0x10,$inp));
	&movdqu	($rndkey1,&QWP(0x20,$inp));
	&pxor	($inout0,$ivec);
	&pxor	($inout1,$in0);
	&movdqu	($ivec,&QWP(0x30,$inp));
	&movdqu	(&QWP(0,$out),$inout0);
	&pxor	($inout2,$rndkey0);
	&pxor	($inout3,$rndkey1);
	&movdqu	(&QWP(0x10,$out),$inout1);
	&movdqu	(&QWP(0x20,$out),$inout2);
	&movdqa	($inout0,$inout3);
	&lea	($out,&DWP(0x30,$out));
	&jmp	(&label("cbc_dec_tail_collected"));

&set_label("cbc_dec_one",16);
	if ($inline)
	{   &aesni_inline_generate1("dec");	}
	else
	{   &call	("_aesni_decrypt1");	}
	&pxor	($inout0,$ivec);
	&movdqa	($ivec,$in0);
	&jmp	(&label("cbc_dec_tail_collected"));

&set_label("cbc_dec_two",16);
	&pxor	($inout2,$inout2);
	&call	("_aesni_decrypt3");
	&pxor	($inout0,$ivec);
	&pxor	($inout1,$in0);
	&movdqu	(&QWP(0,$out),$inout0);
	&movdqa	($inout0,$inout1);
	&movdqa	($ivec,$in1);
	&lea	($out,&DWP(0x10,$out));
	&jmp	(&label("cbc_dec_tail_collected"));

&set_label("cbc_dec_three",16);
	&call	("_aesni_decrypt3");
	&pxor	($inout0,$ivec);
	&pxor	($inout1,$in0);
	&pxor	($inout2,$in1);
	&movdqu	(&QWP(0,$out),$inout0);
	&movdqu	(&QWP(0x10,$out),$inout1);
	&movdqa	($inout0,$inout2);
	&movdqu	($ivec,&QWP(0x20,$inp));
	&lea	($out,&DWP(0x20,$out));

&set_label("cbc_dec_tail_collected");
	&and	($len,15);
	&jnz	(&label("cbc_dec_tail_partial"));
	&movdqu	(&QWP(0,$out),$inout0);
	&jmp	(&label("cbc_ret"));

&set_label("cbc_dec_tail_partial",16);
	&mov	($key_,"esp");
	&sub	("esp",16);
	&and	("esp",-16);
	&movdqa	(&QWP(0,"esp"),$inout0);
	&mov	($inp,"esp");
	&mov	("ecx",$len);
	&data_word(0xA4F3F689);		# rep movsb
	&mov	("esp",$key_);

&set_label("cbc_ret");
	&mov	($key_,&wparam(4));
	&movups	(&QWP(0,$key_),$ivec);	# output IV
&function_end("${PREFIX}_cbc_encrypt");

######################################################################
# Mechanical port from aesni-x86_64.pl.
#
# _aesni_set_encrypt_key is private interface,
# input:
#	"eax"	const unsigned char *userKey
#	$rounds	int bits
#	$key	AES_KEY *key
# output:
#	"eax"	return code
#	$round	rounds

&function_begin_B("_aesni_set_encrypt_key");
	&test	("eax","eax");
	&jz	(&label("bad_pointer"));
	&test	($key,$key);
	&jz	(&label("bad_pointer"));

	&movups	("xmm0",&QWP(0,"eax"));	# pull first 128 bits of *userKey
	&pxor	("xmm4","xmm4");	# low dword of xmm4 is assumed 0
	&lea	($key,&DWP(16,$key));
	&cmp	($rounds,256);
	&je	(&label("14rounds"));
	&cmp	($rounds,192);
	&je	(&label("12rounds"));
	&cmp	($rounds,128);
	&jne	(&label("bad_keybits"));

&set_label("10rounds",16);
	&mov		($rounds,9);
	&$movekey	(&QWP(-16,$key),"xmm0");	# round 0
	&aeskeygenassist("xmm1","xmm0",0x01);		# round 1
	&call		(&label("key_128_cold"));
	&aeskeygenassist("xmm1","xmm0",0x2);		# round 2
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x04);		# round 3
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x08);		# round 4
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x10);		# round 5
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x20);		# round 6
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x40);		# round 7
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x80);		# round 8
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x1b);		# round 9
	&call		(&label("key_128"));
	&aeskeygenassist("xmm1","xmm0",0x36);		# round 10
	&call		(&label("key_128"));
	&$movekey	(&QWP(0,$key),"xmm0");
	&mov		(&DWP(80,$key),$rounds);
	&xor		("eax","eax");
	&ret();

&set_label("key_128",16);
	&$movekey	(&QWP(0,$key),"xmm0");
	&lea		($key,&DWP(16,$key));
&set_label("key_128_cold");
	&shufps		("xmm4","xmm0",0b00010000);
	&pxor		("xmm0","xmm4");
	&shufps		("xmm4","xmm0",0b10001100,);
	&pxor		("xmm0","xmm4");
	&pshufd		("xmm1","xmm1",0b11111111);	# critical path
	&pxor		("xmm0","xmm1");
	&ret();

&set_label("12rounds",16);
	&movq		("xmm2",&QWP(16,"eax"));	# remaining 1/3 of *userKey
	&mov		($rounds,11);
	&$movekey	(&QWP(-16,$key),"xmm0")		# round 0
	&aeskeygenassist("xmm1","xmm2",0x01);		# round 1,2
	&call		(&label("key_192a_cold"));
	&aeskeygenassist("xmm1","xmm2",0x02);		# round 2,3
	&call		(&label("key_192b"));
	&aeskeygenassist("xmm1","xmm2",0x04);		# round 4,5
	&call		(&label("key_192a"));
	&aeskeygenassist("xmm1","xmm2",0x08);		# round 5,6
	&call		(&label("key_192b"));
	&aeskeygenassist("xmm1","xmm2",0x10);		# round 7,8
	&call		(&label("key_192a"));
	&aeskeygenassist("xmm1","xmm2",0x20);		# round 8,9
	&call		(&label("key_192b"));
	&aeskeygenassist("xmm1","xmm2",0x40);		# round 10,11
	&call		(&label("key_192a"));
	&aeskeygenassist("xmm1","xmm2",0x80);		# round 11,12
	&call		(&label("key_192b"));
	&$movekey	(&QWP(0,$key),"xmm0");
	&mov		(&DWP(48,$key),$rounds);
	&xor		("eax","eax");
	&ret();

&set_label("key_192a",16);
	&$movekey	(&QWP(0,$key),"xmm0");
	&lea		($key,&DWP(16,$key));
&set_label("key_192a_cold",16);
	&movaps		("xmm5","xmm2");
&set_label("key_192b_warm");
	&shufps		("xmm4","xmm0",0b00010000);
	&movaps		("xmm3","xmm2");
	&pxor		("xmm0","xmm4");
	&shufps		("xmm4","xmm0",0b10001100);
	&pslldq		("xmm3",4);
	&pxor		("xmm0","xmm4");
	&pshufd		("xmm1","xmm1",0b01010101);	# critical path
	&pxor		("xmm2","xmm3");
	&pxor		("xmm0","xmm1");
	&pshufd		("xmm3","xmm0",0b11111111);
	&pxor		("xmm2","xmm3");
	&ret();

&set_label("key_192b",16);
	&movaps		("xmm3","xmm0");
	&shufps		("xmm5","xmm0",0b01000100);
	&$movekey	(&QWP(0,$key),"xmm5");
	&shufps		("xmm3","xmm2",0b01001110);
	&$movekey	(&QWP(16,$key),"xmm3");
	&lea		($key,&DWP(32,$key));
	&jmp		(&label("key_192b_warm"));

&set_label("14rounds",16);
	&movups		("xmm2",&QWP(16,"eax"));	# remaining half of *userKey
	&mov		($rounds,13);
	&lea		($key,&DWP(16,$key));
	&$movekey	(&QWP(-32,$key),"xmm0");	# round 0
	&$movekey	(&QWP(-16,$key),"xmm2");	# round 1
	&aeskeygenassist("xmm1","xmm2",0x01);		# round 2
	&call		(&label("key_256a_cold"));
	&aeskeygenassist("xmm1","xmm0",0x01);		# round 3
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x02);		# round 4
	&call		(&label("key_256a"));
	&aeskeygenassist("xmm1","xmm0",0x02);		# round 5
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x04);		# round 6
	&call		(&label("key_256a"));
	&aeskeygenassist("xmm1","xmm0",0x04);		# round 7
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x08);		# round 8
	&call		(&label("key_256a"));
	&aeskeygenassist("xmm1","xmm0",0x08);		# round 9
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x10);		# round 10
	&call		(&label("key_256a"));
	&aeskeygenassist("xmm1","xmm0",0x10);		# round 11
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x20);		# round 12
	&call		(&label("key_256a"));
	&aeskeygenassist("xmm1","xmm0",0x20);		# round 13
	&call		(&label("key_256b"));
	&aeskeygenassist("xmm1","xmm2",0x40);		# round 14
	&call		(&label("key_256a"));
	&$movekey	(&QWP(0,$key),"xmm0");
	&mov		(&DWP(16,$key),$rounds);
	&xor		("eax","eax");
	&ret();

&set_label("key_256a",16);
	&$movekey	(&QWP(0,$key),"xmm2");
	&lea		($key,&DWP(16,$key));
&set_label("key_256a_cold");
	&shufps		("xmm4","xmm0",0b00010000);
	&pxor		("xmm0","xmm4");
	&shufps		("xmm4","xmm0",0b10001100);
	&pxor		("xmm0","xmm4");
	&pshufd		("xmm1","xmm1",0b11111111);	# critical path
	&pxor		("xmm0","xmm1");
	&ret();

&set_label("key_256b",16);
	&$movekey	(&QWP(0,$key),"xmm0");
	&lea		($key,&DWP(16,$key));

	&shufps		("xmm4","xmm2",0b00010000);
	&pxor		("xmm2","xmm4");
	&shufps		("xmm4","xmm2",0b10001100);
	&pxor		("xmm2","xmm4");
	&pshufd		("xmm1","xmm1",0b10101010);	# critical path
	&pxor		("xmm2","xmm1");
	&ret();

&set_label("bad_pointer",4);
	&mov	("eax",-1);
	&ret	();
&set_label("bad_keybits",4);
	&mov	("eax",-2);
	&ret	();
&function_end_B("_aesni_set_encrypt_key");

# int $PREFIX_set_encrypt_key (const unsigned char *userKey, int bits,
#                              AES_KEY *key)
&function_begin_B("${PREFIX}_set_encrypt_key");
	&mov	("eax",&wparam(0));
	&mov	($rounds,&wparam(1));
	&mov	($key,&wparam(2));
	&call	("_aesni_set_encrypt_key");
	&ret	();
&function_end_B("${PREFIX}_set_encrypt_key");

# int $PREFIX_set_decrypt_key (const unsigned char *userKey, int bits,
#                              AES_KEY *key)
&function_begin_B("${PREFIX}_set_decrypt_key");
	&mov	("eax",&wparam(0));
	&mov	($rounds,&wparam(1));
	&mov	($key,&wparam(2));
	&call	("_aesni_set_encrypt_key");
	&mov	($key,&wparam(2));
	&shl	($rounds,4)	# rounds-1 after _aesni_set_encrypt_key
	&test	("eax","eax");
	&jnz	(&label("dec_key_ret"));
	&lea	("eax",&DWP(16,$key,$rounds));	# end of key schedule

	&$movekey	("xmm0",&QWP(0,$key));	# just swap
	&$movekey	("xmm1",&QWP(0,"eax"));
	&$movekey	(&QWP(0,"eax"),"xmm0");
	&$movekey	(&QWP(0,$key),"xmm1");
	&lea		($key,&DWP(16,$key));
	&lea		("eax",&DWP(-16,"eax"));

&set_label("dec_key_inverse");
	&$movekey	("xmm0",&QWP(0,$key));	# swap and inverse
	&$movekey	("xmm1",&QWP(0,"eax"));
	&aesimc		("xmm0","xmm0");
	&aesimc		("xmm1","xmm1");
	&lea		($key,&DWP(16,$key));
	&lea		("eax",&DWP(-16,"eax"));
	&$movekey	(&QWP(16,"eax"),"xmm0");
	&$movekey	(&QWP(-16,$key),"xmm1");
	&cmp		("eax",$key);
	&ja		(&label("dec_key_inverse"));

	&$movekey	("xmm0",&QWP(0,$key));	# inverse middle
	&aesimc		("xmm0","xmm0");
	&$movekey	(&QWP(0,$key),"xmm0");

	&xor		("eax","eax");		# return success
&set_label("dec_key_ret");
	&ret	();
&function_end_B("${PREFIX}_set_decrypt_key");
&asciz("AES for Intel AES-NI, CRYPTOGAMS by <appro\@openssl.org>");

&asm_finish();
