"""Isolated iOS TLS fixture generation; never installs certificates."""
from pathlib import Path
from datetime import datetime,timedelta,timezone
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID,ExtendedKeyUsageOID
out=Path(__file__).resolve().parents[1]/'work/ios-certificates';out.mkdir(exist_ok=True)
now=datetime.now(timezone.utc)
def cert(name,k,issuer=None,signer=None,ca=False,expired=False,names=None):
 b=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)])).issuer_name(issuer.subject if issuer else x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)])).public_key(k.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=10)).not_valid_after(now+timedelta(days=-1 if expired else 30)).add_extension(x509.BasicConstraints(ca=ca,path_length=1 if ca else None),True).add_extension(x509.KeyUsage(digital_signature=True,content_commitment=False,key_encipherment=not ca,data_encipherment=False,key_agreement=False,key_cert_sign=ca,crl_sign=ca,encipher_only=None,decipher_only=None),True)
 if not ca:b=b.add_extension(x509.SubjectAlternativeName(names or [x509.DNSName(name)]),False).add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),False)
 return b.sign(signer or k,hashes.SHA256())
def key():return rsa.generate_private_key(public_exponent=65537,key_size=2048)
def save(name,c,k=None):
 (out/(name+'.der')).write_bytes(c.public_bytes(serialization.Encoding.DER));(out/(name+'.pem')).write_bytes(c.public_bytes(serialization.Encoding.PEM))
 if k:
  p=out/(name+'.key');p.write_bytes(k.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()));p.chmod(0o600)
rk=key();root=cert('WAI iOS Root',rk,ca=True);save('root',root)
ik=key();inter=cert('WAI iOS Intermediate',ik,root,rk,True);save('intermediate',inter)
for name,host,expired in [('allowed','allowed.127.0.0.1.nip.io',False),('cdn','static.allowed.127.0.0.1.nip.io',False),('outside','outside.127.0.0.1.nip.io',False),('expired','allowed.127.0.0.1.nip.io',True)]:
 k=key();c=cert(host,k,inter,ik,expired=expired);save(name,c,k);(out/(name+'-chain.pem')).write_bytes(c.public_bytes(serialization.Encoding.PEM)+inter.public_bytes(serialization.Encoding.PEM))
wrongkey=key();wrong=cert('Unrelated root',wrongkey,ca=True);k=key();c=cert('allowed.127.0.0.1.nip.io',k,wrong,wrongkey);save('wrong',c,k);(out/'wrong-chain.pem').write_bytes(c.public_bytes(serialization.Encoding.PEM)+wrong.public_bytes(serialization.Encoding.PEM))

k=key(); c=cert('allowed.127.0.0.1.nip.io',k,inter,ik,names=[x509.DNSName('allowed.127.0.0.1.nip.io'),x509.DNSName('outside.127.0.0.1.nip.io')]);save('mixed',c,k)
import ipaddress
k=key(); c=cert('allowed.127.0.0.1.nip.io',k,inter,ik,names=[x509.DNSName('allowed.127.0.0.1.nip.io'),x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]);save('ip-san',c,k)
k=key(); c=cert('*.allowed.127.0.0.1.nip.io',k,inter,ik);save('wildcard',c,k)
