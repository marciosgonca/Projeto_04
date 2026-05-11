Import-Module ActiveDirectory

# ========= CONFIGURAÇÕES =========
$DiasInatividade = 180
$OU_Destino = "OU=Usuarios_Inativos,DC=empresa,DC=local"
$CaminhoRelatorio = "C:\Relatorios_AD"

$DataCorte = (Get-Date).AddDays(-$DiasInatividade)

# Criar pasta de relatórios se não existir
if (!(Test-Path $CaminhoRelatorio)) {
    New-Item -ItemType Directory -Path $CaminhoRelatorio
}

# Arquivos de relatório
$RelUsuarios = "$CaminhoRelatorio\Usuarios_Inativos.csv"
$RelGrupos   = "$CaminhoRelatorio\Grupos_Usuarios.csv"
$RelAcoes    = "$CaminhoRelatorio\Acoes_Executadas.csv"

# ========= COLETAR USUÁRIOS =========
$Usuarios = Get-ADUser -Filter * -Properties LastLogonDate, MemberOf |
Where-Object {
    $_.Enabled -eq $true -and
    ($_.LastLogonDate -lt $DataCorte -or $_.LastLogonDate -eq $null)
}

# ========= EXPORTAR USUÁRIOS =========
$Usuarios | Select-Object `
    Name,
    SamAccountName,
    DistinguishedName,
    LastLogonDate |
Export-Csv $RelUsuarios -NoTypeInformation -Encoding UTF8

# ========= PROCESSAR CONTAS =========
$Acoes = @()
$ListaGrupos = @()

foreach ($User in $Usuarios) {

    Write-Host "Processando usuário: $($User.SamAccountName)" -ForegroundColor Yellow

    # --- Exportar grupos ---
    $Grupos = Get-ADPrincipalGroupMembership $User | Where-Object {
        $_.Name -ne "Domain Users"
    }

    foreach ($Grupo in $Grupos) {
        $ListaGrupos += [PSCustomObject]@{
            Usuario = $User.SamAccountName
            Grupo   = $Grupo.Name
        }
    }

    # --- Mover para OU ---
    Move-ADObject -Identity $User.DistinguishedName -TargetPath $OU_Destino

    # --- Desabilitar conta ---
    Disable-ADAccount -Identity $User.SamAccountName

    # --- Remover dos grupos ---
    foreach ($Grupo in $Grupos) {
        Remove-ADGroupMember -Identity $Grupo -Members $User -Confirm:$false
    }

    # --- Registrar ação ---
    $Acoes += [PSCustomObject]@{
        Usuario        = $User.SamAccountName
        UltimoLogon    = $User.LastLogonDate
        AcoesExecutadas = "Movido OU / Desabilitado / Removido Grupos / Excluído"
        DataExecucao   = Get-Date
    }

    # --- Excluir conta ---
    Remove-ADUser -Identity $User.SamAccountName -Confirm:$false
}

# ========= EXPORTAR RELATÓRIOS =========
$ListaGrupos | Export-Csv $RelGrupos -NoTypeInformation -Encoding UTF8
$Acoes | Export-Csv $RelAcoes -NoTypeInformation -Encoding UTF8

Write-Host "`n✅ Processo finalizado com sucesso!" -ForegroundColor Green
Write-Host "Relatórios gerados em: $CaminhoRelatorio"