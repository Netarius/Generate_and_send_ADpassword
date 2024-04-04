Import-Module activedirectory
Add-Type -AssemblyName System.Web

function Imobis
{
  param(
    [Parameter(Mandatory = $True)] [string]$phone, [Parameter(Mandatory = $True)] [string]$sms
  )
  $Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $Headers.Add("Authorization","Token bf6e06d1-b9b4-44d8-8d71-9de85b6ff262")
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $body = @{
    sender = "Your Company"
    phone = $phone
    text = $sms
    report = "https://imobisapi.yourdomain.ru/public/imobiserr/logerr"
  }
  $body = $body | ConvertTo-Json
  try {
    $DisableResponse = Invoke-RestMethod "https://api.imobis.ru/v3/message/sendSMS/" -Headers $Headers -Method Post -Body $body -ContentType "application/json; charset=utf-8"
    $global:status = $DisableResponse.status
    $global:id = $DisableResponse.id
  } catch {
    $result = $_.Exception
  }
  return $result
}

#Генерация пароля в соответствии с требованиями безопасности
Function Generate-Complex-Domain-Password ([Parameter(Mandatory=$true)][int]$PassLenght) {
    $ascii_lowercase = 'acefhjkmnpqrtuvwxy'
    $ascii_uppercase = 'ACEFHJKMNPQRTUVWXY'
    $digits = '12345679'
    $puct = '@#$%&'
    $Password = $null
    $ascii_lowercase.ToCharArray() | Get-Random -Count ($PassLenght-5) | ForEach-Object {$Password += $_}
    $ascii_uppercase.ToCharArray() | Get-Random -Count 2 | ForEach-Object {$Password += $_}
    $digits.ToCharArray() | Get-Random -Count 2 | ForEach-Object {$Password += $_}
    $puct.ToCharArray() | Get-Random -Count 1 | ForEach-Object {$Password += $_}
    $Password = ($Password.ToCharArray() | Sort-Object {Get-Random}) -join $null
    return $Password
}

$UserList = 'C:\scripts\PS\AD\sms_pass\users.txt'
$Success_Log = 'C:\Scripts\PS\AD\SMS-Pass.txt'
$Fail_Log = 'C:\Scripts\PS\AD\No-Phone.txt'
$DateTimeELK = get-date -f "yyyy-MM-dd HH:mm:ss"
Get-Content $UserList | ForEach-Object {
    $Login = $_
    $User = $null
    $User = Get-ADUser -Identity $Login -Properties Description,HomePhone,emailaddress,department,title,msDS-User-Account-Control-Computed
    if ($User) {    
        $Phone = $User.HomePhone
        $Phone = $Phone -replace '[^0-9]+', ""
        $Phone = $Phone -replace "^8", "7"
            
        if ($Phone.length -gt 0) {            
            $wc = New-Object system.Net.WebClient
            $pass = Generate-Complex-Domain-Password (10)
            Set-ADAccountPassword $Login -Reset -NewPassword (ConvertTo-SecureString $pass -AsPlainText -Force -Verbose) –PassThru | Set-ADuser -ChangePasswordAtLogon $False
			$oneclick = pbincli send -t "$pass" -s https://oneclick.yourdomain.ru/ -E 1day -B
       		$oneclick = ($oneclick[7] -replace "Link:","").TrimStart()
            $sms = "Для входа в компьютер`nВаш логин: $Login `nПароль по одноразовой ссылке: $oneclick"
            Imobis -phone $Phone -sms $sms
            $Success_Text = "$DateTimeELK - SMS send to recipient: $Phone, login: $Login, status: $status, id: $id, service: AdUserResetUSER"
            Out-File -FilePath $Success_Log -InputObject $Success_Text -Append -encoding Utf8
        } else {
            $Fail_Text = "$DateTimeELK -  Tel.number not found: $Login, status: $status, service: AdUserResetUSER"
            Out-File -FilePath $Fail_Log -InputObject $Fail_Text -Append -encoding Utf8
        }
    } else {
        $Fail_Text = $Login + " не существует в AD " + (Get-Date -UFormat "%d.%m.%Y %H:%M")
        Out-File -FilePath $Fail_Log -InputObject $Fail_Text -Append -encoding Unicode
    }
}