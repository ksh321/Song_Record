$ErrorActionPreference='Stop'
$inputObject=[Console]::In.ReadToEnd() | ConvertFrom-Json
$directory=[IO.Path]::GetFullPath($inputObject.directory)
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../.local/workflow/validation/https'))
if($directory -ne $root -or -not $inputObject.password){throw 'Validation certificate target invalid'}
$rsa=[Security.Cryptography.RSA]::Create(2048)
try {
 $request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=localhost',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
 $san=[Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new();$san.AddDnsName('localhost');$san.AddIpAddress([Net.IPAddress]::Loopback)
 $request.CertificateExtensions.Add($san.Build())
 $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
 $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,$true))
 $oids=[Security.Cryptography.OidCollection]::new();$null=$oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'));$request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
 $certificate=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddDays(14))
 try {
  [IO.File]::WriteAllBytes((Join-Path $directory 'server.p12'),$certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,[string]$inputObject.password))
  [IO.File]::WriteAllText((Join-Path $directory 'server.crt'),$certificate.ExportCertificatePem())
 } finally {$certificate.Dispose()}
} finally {$rsa.Dispose();$inputObject=$null}
Write-Host 'Private local validation certificate created; no system/browser trust changed'
