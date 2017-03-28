<#
    Primer intento de automatizar y homogeneizar la creación de un usuario perteneciente a un rol
    V0.1
    Ignacio Lis - 17/Sept/2015
#>

#Credenciales harcodeadas
$contraseña = ConvertTo-SecureString "aquíelpassword" -AsPlainText -Force
$credenciales = New-Object System.Management.Automation.PSCredential("usuario",$contraseña)
$passyo = ConvertTo-SecureString "estonosehace" -AsPlainText -Force
$credyo = New-Object System.Management.Automation.PSCredential("usuario",$contraseña)

#Función que lee la definición del rol del XML y realiza las acciones necesarias:
#   · Si el acceso depende de la pertenencia a un grupo del AD, se añade al usuario a ese grupo
#   · Si el acceso depende de la apertura de un ticket se crea un correo para el Service Desk

# TODO
#   · Múltiples peticiones en un mismo cuerpo de correo (p.ej. tickets de añadir a varios buzones)
#     -> Ya está hecho para peticiones sin modelo ni correo, hay que generalizarlo

Function Tareas-Rol{
    Param([string]$defrol,[string]$sam)
    #Leemos el XML que define el rol
    [xml]$role = Get-Content $defrol -Encoding UTF8
    $contador = 1
    $usuario = Get-ADUser -Identity $sam -Properties *
    $numTareas = $role.role.ChildNodes | Measure-Object
    ForEach ($peticion in $role.role.access){
        if ($peticion.type -eq "adgroup"){
            "`t[" + $contador + "/" + $numTareas.Count + "] " + "Ejecutando " + $peticion.name + " para " + $usuario.name
            AñadirA-Grupo -grupo $peticion.group -sam $sam
        }
        elseif ($peticion.type -eq "email") {
            "`t[" + $contador + "/" + $numTareas.Count + "] " + "Solicitando " + $peticion.name + " para " + $usuario.name
            if ($peticion.needsmodel -eq "yes"){
                if ($peticion.needsemail -eq "yes"){
                    Construir-Correo -nombre $usuario.name -acceso $peticion.name -tieneModelo $true -modelo $peticion.modelID -tieneCorreo $true -correo $usuario.mail -esMultiple $false     
                }
                else {
                    Construir-Correo -nombre $usuario.name -acceso $peticion.name -tieneModelo $true -modelo $peticion.modelID -tieneCorreo $false -esMultiple $false
                }
               
            }
            else{
                if ($peticion.needsemail -eq "yes"){
                    Construir-Correo -nombre $usuario.name -acceso $peticion.name -tieneModelo $false -tieneCorreo $true -correo $usuario.mail -esMultiple $false
                }
                else{
                    # TODO - Generalizar
                    if ($peticion.ismultiple -eq "yes"){
                        Construir-Correo -nombre $usuario.name -acceso $peticion.name -tieneModelo $false -tieneCorreo $false -esMultiple $true -listado $peticion.list
                    }
                    else{
                        Construir-Correo -nombre $usuario.name -acceso $peticion.name -tieneModelo $false -tieneCorreo $false -esMultiple $false
                    }
                }
            }
        }
        $contador++  
    }
}

Function AñadirA-Grupo{
    Param([string]$grupo,[string]$sam)
    Add-ADGroupMember -Identity $grupo -Members $sam -Credential $credenciales #-WhatIf
}

Function Construir-Correo{
    Param([string]$nombre,[string]$acceso,[bool]$tieneModelo,[string]$modelo,[string]$correo,[bool]$tieneCorreo,[bool]$esMultiple,[string]$listado)
    $asunto = $acceso + " - " + $nombre
    $origen = "origen@lala.la"
    $destino = "destino@lala.la"
    $conCopiaA = "otro@lala.la"
    $servidor = "smtp.correo.local"
    if ($tieneCorreo){
        $nombre = $nombre + " - " + $correo
    }
    if ($esMultiple){
        $cuerpo = "<p>Buenos días</p><p>Necesitamos que se dé acceso al usuario " + $nombre + " a las siguientes " + $acceso.ToLower() + " con permisos SendAs:</p> `
        <ul><li>" + $listado.Replace("#NL#","<li>") + "</ul>"
    }
    else{
        $cuerpo = "<p>Buenos días</p><p>Necesitamos que se dé acceso al usuario " + $nombre + " a " + $acceso + "</p>"
    }
    if ($tieneModelo){
        $cuerpo += "<p>ModelID: " + $modelo + "</p><p>Muchas gracias</p>"    
    }
    else{
        $cuerpo += "<p>Muchas gracias</p>"
    }
    Send-MailMessage -To $destino -cc $conCopiaA -From $origen -Subject $asunto -Body $cuerpo -SmtpServer $servidor -Encoding UTF8 -BodyAsHtml -Credential $credyo
}

#Leemos los usuarios a crear y sus tareas
$listaUsuarios = Import-Csv .\autorol.csv -Delimiter ";" -Encoding UTF8
$numUsuarios = $listaUsuarios | Measure-Object
$contUsuarios = 1
$listaUsuarios | ForEach-Object {
    $usuActual = Get-ADUser -Identity $_.sam -Properties *
    "[" + $contUsuarios + "/" + $numUsuarios.Count + "] Añadiendo a " + $usuActual.name
    $ruta = $_.rol
    Tareas-Rol -defrol $ruta -sam $_.sam
    $contUsuarios++
}
