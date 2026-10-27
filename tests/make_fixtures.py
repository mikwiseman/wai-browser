"""Ephemeral CA fixtures; no system/keychain installation."""
from pathlib import Path
import ipaddress
from datetime import datetime,timedelta,timezone
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID,ExtendedKeyUsageOID
out=Path(__file__).resolve().parents[1]/'work/test-certificates'
out.mkdir(parents=True,exist_ok=True)
now=datetime.now(timezone.utc)
def key(): return rsa.generate_private_key(public_exponent=65537,key_size=2048)
def cert(name,k,issuer=None,signer=None,ca=False,expired=False):
 subject=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)])
 b=x509.CertificateBuilder().subject_name(subject).issuer_name(issuer.subject if issuer else subject).public_key(k.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=10)).not_valid_after(now+timedelta(days=-1 if expired else 30)).add_extension(x509.BasicConstraints(ca=ca,path_length=1 if ca else None),critical=True).add_extension(x509.KeyUsage(digital_signature=True,content_commitment=False,key_encipherment=not ca,data_encipherment=False,key_agreement=False,key_cert_sign=ca,crl_sign=ca,encipher_only=None,decipher_only=None),critical=True)
 if not ca: b=b.add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(name)) if name in {"127.0.0.1","::1"} else x509.DNSName(name)]),False).add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),False)
 return b.sign(signer or k,hashes.SHA256())
def save(name,c,k=None):
 (out/(name+'.der')).write_bytes(c.public_bytes(serialization.Encoding.DER))
 (out/(name+'.pem')).write_bytes(c.public_bytes(serialization.Encoding.PEM))
 if k:
  p=out/(name+'.key');p.write_bytes(k.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()));p.chmod(0o600)
rk=key();root=cert('WAI Test Root',rk,ca=True);save('root',root)
ik=key();intermediate=cert('WAI Test Intermediate',ik,root,rk,True);save('intermediate',intermediate)
for name,hostname,expired in [('allowed','allowed.wai.test',False),('outside','outside.wai.test',False),('expired','allowed.wai.test',True),('cdn','static.allowed.wai.test',False),('ip','127.0.0.1',False),('ip6','::1',False),('spoof','allowed.wai.test.evil.test',False)]:
 k=key();c=cert(hostname,k,intermediate,ik,expired=expired);save(name,c,k)
 (out/(name+'-chain.pem')).write_bytes(c.public_bytes(serialization.Encoding.PEM)+intermediate.public_bytes(serialization.Encoding.PEM))
wrongkey=key();wrong=cert('Wrong Root',wrongkey,ca=True);save('wrong-root',wrong)
k=key();c=cert('allowed.wai.test',k,wrong,wrongkey);save('wrong',c,k);(out/'wrong-chain.pem').write_bytes(c.public_bytes(serialization.Encoding.PEM)+wrong.public_bytes(serialization.Encoding.PEM))
print(out)
