{
   locate07.pas
   
   Copyright 2020 Ricardo Jurczyk Pinheiro <ricardo@aragorn>
  
* Este código pode ate ser rodado no PC, mas a prioridade e o MSX.
* Ele vai ler o arquivo de hashes (que esta compactado com um metodo de
* RLE) e jogar para um vetor na memoria. O programa vai pedir um padrao 
* de busca. O programa coloca o padrao todo em maiusculas - o MSX-DOS 
* nao diferencia. Ele calcula o hash desse padrao de busca, faz-se uma 
* busca binaria nesse vetor de hashes e, achando, le o registro no 
* arquivo de registros, colocando a informacao na tela. Acrescentei um 
* trecho de codigo para procurar por colisoes (com base no hash) e 
* imprimir todas as entradas identicas.
}

program locate07;

{$i d:types.inc}
{$i d:memory.inc}
{$i d:dos.inc}
{$i d:dos2file.inc}
{$i d:dos2err.inc}
{$i d:dpb.inc}
{$i d:fastwrit.inc}
    
const
    TamanhoBuffer = 255;
    TamanhoNomeArquivo = 40;
    TamanhoTotalBuffer = 255;
    TamanhoDiretorio = 127;
    MaximoRegistros = 8700;
    HashesPorLinha = 36;

type
    BufferVector = string[TamanhoBuffer];
    Registro = record
        hash: integer;
        NomeDoArquivo: string[TamanhoNomeArquivo];
        Diretorio: string[TamanhoDiretorio];
    end;
    HashVector = array[1..MaximoRegistros] of integer;
    
var
(*  Variaveis relacionadas aos arquivos. *)
    ResultadoSeek: boolean;
    ResultadoBlockRead: byte;
    ArquivoRegistros, ArquivoHashes: byte;
    NovaPosicao: integer;
    NomeArquivoRegistros, NomeArquivoHashes: TFileName;
    
(*  Usado pelas rotinas que verificam a versão do MSX-DOS e a letra de drive. *)
    VersaoMSXDOS : TMSXDOSVersion;
    Registros: TRegs;
    LetraDeDrive: char;
    
(*  Vetores, de hashes e de parâmetros.  *)    
    VetorHashes: HashVector;
    VetorParametros: array [1..4] of TFileName;
    HashEmTexto, TemporarioNumero: string[8];
    Ficha: Registro;

(*  Inteiros. *)
    Posicao, Tamanho, Tentativas, Acima, Abaixo, RetornoDoVal: integer;
    LimiteDeBuscas: integer;
    i, b, ModuloDoHash, TotalDeRegistros, HashTemporario: integer;

(*  Caracteres. *)
    Caractere, PrimeiraLetra: char;

(*  O buffer usado para leitura dos arquivos. *)
(*    buffer: BufferVector;         *)
    vetorbuffer: array[0..255] of byte;
    
(*  Ainda tem que faxinar esse trecho aqui. *)    
(*  Mudar esse bando de temporarios para um vetor de temporarios *)    
    pesquisa, temporario: TFileName;
    Caminho: TFileName;
    j, hash, contador: integer;
    parametro: byte;
    letra: char;

function LastPos(Caractere: char; Frase: TString): integer;
var
    i: integer;
    Encontrou: boolean;
begin
    i := length(Frase);
    Encontrou := false;
    repeat
        if Frase[i] = Caractere then
        begin
            LastPos := i + 1;
            Encontrou := true;
        end;
        i := i - 1;
    until Encontrou = true;
end;

procedure BuscaBinariaNomeDoArquivo (hash, fim: integer; var Posicao, Tentativas: integer);
var
    comeco, meio: integer;
    encontrou: boolean;
    
begin
    comeco		:=	1;
    Tentativas	:=	1;
    fim			:=	TotalDeRegistros;
    encontrou	:=	false;
    while (comeco <= fim) and (encontrou = false) do
    begin
        meio:=(comeco + fim) div 2;
{
        writeln('Comeco: ',comeco,' Meio: ',meio,' fim: ',fim,' hash: ',hash,' Pesquisa: ',VetorHashes[meio]);
}       
        if (hash = VetorHashes[meio]) then
            encontrou := true
        else
            if (hash < VetorHashes[meio]) then
                fim := meio - 1
            else
                comeco := meio + 1;
        Tentativas := Tentativas + 1;
    end;
    if encontrou = true then
        Posicao := meio;
end;

procedure CodigoDeErro (SaiOuNao: boolean);
var
    NumeroDoCodigoDeErro: byte;
    MensagemDeErro     : TMSXDOSString;
    
begin
    NumeroDoCodigoDeErro := GetLastErrorCode;
    GetErrorMessage( NumeroDoCodigoDeErro, MensagemDeErro );
    WriteLn( MensagemDeErro );
    if SaiOuNao = true then
        Exit;
end;

procedure LeFichaNoArquivoRegistros (Posicao: integer; var Ficha: Registro);
var
    lidos, contador: integer;
    inicio, fim: integer;
    fimdoarquivo: boolean;
    frase: string[TamanhoBuffer];

begin
    RetornoDoVal:=0;
    HashEmTexto:='';

    fillchar(vetorbuffer, sizeof (vetorbuffer), ' ' );
    fillchar(frase, sizeof (frase), ' ' );

    ResultadoSeek := FileSeek (ArquivoRegistros, 0, ctSeekSet, NovaPosicao);

    For contador := 1 To Posicao + 1 do
        If (not FileSeek(ArquivoRegistros, TamanhoBuffer, ctSeekCur, NovaPosicao)) Then
            CodigoDeErro (true);

    ResultadoBlockRead := FileBlockRead(ArquivoRegistros, vetorbuffer, TamanhoBuffer);
{
writeln('Contador -> ',contador, ' Posicao: ', Posicao, ' NovaPosicao: ', NovaPosicao);
}
    contador := 1; 
    
    while letra <> '#' do
    begin
        letra := char(vetorbuffer[contador]);
        contador := contador + 1;
    end;
    
    inicio := contador;
    
    contador := TamanhoBuffer;
    
    while letra <> ',' do
    begin
        letra := char(vetorbuffer[contador]);
        contador := contador - 1;
    end;
    
    fim := contador + 1; 
{
    writeln('Inicio: ', inicio, ' Fim: ', fim);
    writeln('Frase: ', frase);
}
    delete(frase, 1, TamanhoBuffer);
    for contador := inicio to fim do
    begin
        letra := char(vetorbuffer[contador]);
        frase:= concat(frase, letra);
    end;
    frase[0] := char(fim - inicio);

(* Copia o Diretorio e apaga o que nao sera usado *)
    Ficha.Diretorio := copy(frase, LastPos(',', frase), TamanhoBuffer);
    delete(frase, LastPos(',', frase) - 1, TamanhoBuffer);
{
    writeln('Diretorio: ', Ficha.Diretorio);
    writeln('Frase: ', frase);
}
(* Copia o nome do arquivo e apaga o que nao sera usado *)
    Ficha.NomeDoArquivo := copy(frase, LastPos(',', frase), TamanhoBuffer);
    delete(frase, LastPos(',', frase) - 1, TamanhoBuffer);
{
     writeln('Arquivo: ', Ficha.NomeDoArquivo);  
     writeln('Frase: ', frase);
}

(* Copia o hash do nome do arquivo e apaga o que nao sera usado *)      

    fillchar(HashEmTexto, length(HashEmTexto), byte( ' ' ));
    HashEmTexto := copy(frase, LastPos(',', frase), TamanhoBuffer);
    delete(frase, LastPos(',', frase) - 1, TamanhoBuffer);
    val(HashEmTexto, hash, RetornoDoVal);
    Ficha.hash := hash;
{
    writeln('Hash: ', Ficha.hash);
    writeln('Hash: ', HashEmTexto);
    writeln('Frase: ', frase);
}
end;

function CalculaHash (NomeDoArquivo: TFileName): integer;
var
    i, hash: integer;
    a, hash2: real;
    
begin
    hash:=0;
    hash2:=0.0;
    for i:=1 to length(NomeDoArquivo) do
    begin
(*  Aqui temos um problema. A funcao ModuloDoHash nao pode ser usada com
    reais e foi necessario usar reais porque o valor e muito grande
    para trabalhar com inteiros - estoura o LimiteDeBuscas.
    Modulo = resto da divisao inteira: c <- a - b * (a / b).
*)
        a := (hash2 * b + ord(NomeDoArquivo[i]));
        hash2 := (a - ModuloDoHash * int(a / ModuloDoHash));
        hash := round(hash2);
    end;
    CalculaHash := hash;
end;

procedure LeArquivoDeHashes(hash, Tamanho, TotalDeRegistros: integer);
var
    registros, entradas, posicao, linha, repeticoes: integer;
    fimdoarquivo: boolean;
    SizeBuffer: integer;
    HashEmTexto: string[8];
    
begin
(* Le com um blockread e separa, jogando cada hash em uma posicao em um vetor. *)
    SizeBuffer := sizeof(vetorbuffer);
    linha := 1;
    entradas := 0;
    HashEmTexto := ' ';
    fimdoarquivo := false;
    
    fillchar(VetorHashes, sizeof (VetorHashes), 0);
{
	writeln('hash: ',hash,' Tamanho: ',Tamanho,' TotalDeRegistros: ',TotalDeRegistros);

    writeln('Posicao Nova: ',NovaPosicao);
}
	while ( not fimdoarquivo ) { or (linha < (Tamanho - 1))} do
    begin
        fillchar(vetorbuffer, sizeof (vetorbuffer), ' ' );
        ResultadoSeek := FileSeek (ArquivoHashes,    0, ctSeekSet, NovaPosicao);
{
writeln('Linha -> ', linha);
}    
(*  Move o ponteiro pro registro a ser lido. *)

        for contador := 1 to linha do
            if not (FileSeek (ArquivoHashes, SizeBuffer, ctSeekCur, NovaPosicao)) then
                CodigoDeErro (true);
        ResultadoBlockRead := FileBlockRead (ArquivoHashes, vetorbuffer, SizeBuffer);
        
        if (ResultadoBlockRead = ctReadWriteError) then
        begin
            CodigoDeErro (false);
            fimdoarquivo := true;
        end;
{
writeln('ResultadoBlockRead: ', ResultadoBlockRead, ' NovaPosicao: ', NovaPosicao);
}
(*  Tem q zerar esses 2 primeiros registros pra não dar problema. *)

        vetorbuffer[0] := ord('0');
        vetorbuffer[1] := ord('0');

(*  Agora precisamos dar um chega pra cá no vetor. *)        

        for posicao := 2 to (SizeBuffer - 1) do
        begin
            letra := Char(vetorbuffer[posicao]);
            vetorbuffer[posicao - 2] := ord(letra);
        end;
{
for posicao := 0 to (SizeBuffer - 1) do
    write(Char(vetorbuffer[posicao]));
writeln; 
}
(*  Agora vamos vasculhar todo o arquivo, para pegar os hashes. *)
        letra := ' ';
   
        for posicao := 1 to HashesPorLinha do
        begin

(*  Aqui, pegamos os dados do vetor de bytes. *)
            contador := 0;
            fillchar(HashEmTexto, sizeof(HashEmTexto), ' ' );
            while letra <> ',' do
            begin
                letra := chr(vetorbuffer[(contador + 7 * (posicao - 1))]);
{
                writeln('letra: ',letra, ' contador: ',contador, 
                    ' (contador + 7 * (posicao - 1)): ', (contador + 7 * (posicao - 1)));
}                
                HashEmTexto[contador + 1] := letra;                
                contador := contador + 1;
            end;
{            
            writeln (length(HashEmTexto));
}            

            HashEmTexto[0] := chr(length(HashEmTexto));

            letra := HashEmTexto[contador - 1];
            delete(HashEmTexto, contador - 1, length(HashEmTexto));
            val(HashEmTexto, hash, RetornoDoVal);
{
                writeln('contador: ', contador, ' Hash em texto: ', HashEmTexto, ' Letra: ', letra,
                    ' Hash: ', hash, ' RetornoDoVal: ', RetornoDoVal);
}
            VetorHashes[entradas] := hash;

(*  Aqui, com base no conteudo pegamos os dados do vetor de bytes. *)

            for repeticoes := 1 to (ord ( letra ) - 64) do
            begin
                VetorHashes[entradas + repeticoes] := hash;               
{
writeln('hash: ', hash, ' entradas: ', entradas, ' repeticoes: ',  repeticoes, 
' VetorHashes[', entradas + repeticoes, ']=', VetorHashes[entradas + repeticoes]);
}            
            end;
            
            entradas := entradas + repeticoes;
{          
            writeln('entradas: ', entradas, ' contador: ', contador, ' posicao: ', posicao);
}          
        end;
{
		writeln('Linha: ',linha,' Total De Registros: ',TotalDeRegistros,' entrada: ',entradas,' tamanho: ',tamanho);
}
        linha := linha + 1;
        if (linha = Tamanho) then
            fimdoarquivo := true;
    end;
{
    for posicao := 1 to TotalDeRegistros do
        writeln('VetorHashes[',posicao,']=',VetorHashes[posicao]);
}
end;

procedure LocateAjuda;
begin
    fastwriteln(' Uso: locate <padrao> <parametros>.');
    fastwriteln(' Faz buscas em um banco de dados criado com a lista de arquivos do dispositivo.');
    fastwriteln(' ');
    fastwriteln(' Padrao: Padrao a ser buscado no banco de dados.');
    fastwriteln(' ');
    fastwriteln(' Parametros: ');
    fastwriteln(' /a ou /change    - Muda para o Diretorio onde o arquivo esta.');
    fastwriteln(' /c ou /count     - Mostra quantas entradas foram encontradas.');
    fastwriteln(' /h ou /help      - Traz este texto de ajuda e sai.');
    fastwriteln(' /l n ou /limit n - Limita a saida para n entradas.');
    fastwriteln(' /p ou /prolix    - Mostra tudo o que o comando esta fazendo.');
    fastwriteln(' /s ou /stats     - Exibe estatisticas do banco de dados.');
    fastwriteln(' /v ou /version   - Exibe a versao do comando e sai.');
    fastwriteln(' ');
    exit;
end;

procedure LocateVersao;
begin
    fastwriteln('locate VersaoMSXDOS 0.1'); 
    fastwriteln('Copyright (c) 2020 Brazilian MSX Crew.');
    fastwriteln('Alguns direitos reservados.');
    fastwriteln('Este software e distribuido segundo a licenca GPL.');
    fastwriteln(' ');
    fastwriteln('Este programa e fornecido sem garantias na medida do permitido pela lei.');
    fastwriteln(' ');
    fastwriteln('Notas de VersaoMSXDOS: ');
    fastwriteln('No momento, esse comando apenas faz busca por nomes exatos de arquivos');
    fastwriteln('no banco de dados. Ele ainda nao faz buscas em nomes incompletos ou em');
    fastwriteln('diretorios. Ele tambem so faz uso de um parametro por vez.');
    fastwriteln('No futuro, teremos o uso de dois ou mais parametros, faremos a busca em');
    fastwriteln('nomes incompletos, diretorios e sera possivel executar o comando CD para');
    fastwriteln('o Diretorio onde o arquivo esta.');
    fastwriteln(' ');
    fastwriteln('Configuracao: ');
    fastwriteln('A principio o banco de dados do locate esta localizado em a:\UTILS\LOCATE\DB.');
    fastwriteln('Se quiser trocar o Caminho, voce deve alterar a variavel de ambiente LOCALEDB,');
    fastwriteln('no MSX-DOS. Faca essas alteracoes no AUTOEXEC.BAT, usando o comando SET.');
    fastwriteln(' ');
    exit;
end;

procedure BuscaAteAVirgula;
begin
    HashEmTexto := ' ';
    letra :=  ' ';
    repeat
        HashEmTexto := concat(HashEmTexto, letra);
        contador := contador + 1;
        letra := chr(vetorbuffer[contador]);
    until letra = ',';
    
    HashEmTexto[0] := char(length(HashEmTexto));
    
    for j := 1 to 2 do
        HashEmTexto[j] := '0';
end;

BEGIN
    parametro := 0;
    LimiteDeBuscas := 0;
    temporario := ' ';

    clrscr;

    GetMSXDOSVersion (VersaoMSXDOS);

    if (VersaoMSXDOS.nKernelMajor < 2) then
    begin
        fastwriteln('MSX-DOS 1.x não suportado.');
        exit;
    end
    else 
        begin
            fillchar(Caminho, TamanhoTotalBuffer, byte( ' ' ));
            temporario[0] := 'l';
            temporario[1] := 'o';
            temporario[2] := 'c';
            temporario[3] := 'a';
            temporario[4] := 'l';
            temporario[5] := 'e';
            temporario[6] := 'd';
            temporario[7] := 'b';
            temporario[8] := #0;
           
            Caminho[0] := #0;
            with Registros do
            begin
                B := sizeof (Caminho);
                C := ctGetEnvironmentItem;
                HL := addr (temporario);
                DE := addr (Caminho);
            end;
       
            MSXBDOS (Registros);
            LetraDeDrive := Caminho[0];
            insert(LetraDeDrive, Caminho, 1);
        end;
        
    if Caminho = '' then Caminho := 'a:\utils\locale\db\'; 
(* Tirar isso na versão final. *)   
   Caminho := 'd:\';
(**)   
    for b := 1 to 4 do
        VetorParametros[b] := paramstr(b);

(* Sem parametros o comando apresenta o help. *)

    if paramcount = 0 then
        LocateAjuda;

(* Antes de tratar como seria com um parametro, pega tudo e passa *)
(* para maiusculas. *)
    
    for j := 1 to 3 do
    begin
        temporario := paramstr(j);
        if pos('/',temporario) <> 0 then
            parametro := j;
        for b := 1 to length(temporario) do
            temporario[b] := upcase(temporario[b]);
        VetorParametros[j] := temporario;
    end;

(* Com um parametro. Se for o /h ou /help, apresenta o help.    *)  
(* Se for o /v ou /version, apresenta a versao do programa.     *)  
    
    Caractere:=' ';
    if (VetorParametros[parametro] = '/A') or (VetorParametros[parametro] = '/CHANGE')    then Caractere := 'A';
    if (VetorParametros[parametro] = '/C') or (VetorParametros[parametro] = '/COUNT')     then Caractere := 'C';
    if (VetorParametros[parametro] = '/H') or (VetorParametros[parametro] = '/HELP')      then LocateAjuda;
    if (VetorParametros[parametro] = '/L') or (VetorParametros[parametro] = '/LIMIT')     then Caractere := 'L';
    if (VetorParametros[parametro] = '/P') or (VetorParametros[parametro] = '/PROLIX')    then Caractere := 'P';
    if (VetorParametros[parametro] = '/S') or (VetorParametros[parametro] = '/STATS')     then Caractere := 'S';
    if (VetorParametros[parametro] = '/V') or (VetorParametros[parametro] = '/VERSION')   then LocateVersao;

    if Caractere = 'L' then
    begin
        val(VetorParametros[parametro + 1], LimiteDeBuscas, RetornoDoVal);
        LimiteDeBuscas := LimiteDeBuscas - 1;
    end;
    
    for b := 1 to 2 do
        if pos('.',VetorParametros[b]) <> 0 then parametro := b;

(* O 1o parametro e o nome a ser pesquisado. *)
    
    pesquisa := VetorParametros[parametro];
{
    NomeArquivoRegistros := 'teste.dat';
    NomeArquivoHashes := 'teste.hsh';
}
    PrimeiraLetra := upcase(pesquisa[1]);
    
    fillchar(NomeArquivoRegistros, sizeof(NomeArquivoRegistros), byte( ' ' ));
    fillchar(NomeArquivoHashes, sizeof(NomeArquivoHashes), byte( ' ' ));
    
    delete(Caminho, LastPos('\',Caminho), sizeof(Caminho));
    
    NomeArquivoRegistros := concat(Caminho, PrimeiraLetra, '.dat');
    NomeArquivoHashes := concat(Caminho, PrimeiraLetra, '.hsh');
{
    writeln(NomeArquivoRegistros);
    writeln(NomeArquivoHashes);
}    
(* Abre os arquivos de registros e de hashes *)

    if Caractere = 'P' then fastwriteln('Abre arquivo de registros');
    ArquivoRegistros := FileOpen (NomeArquivoRegistros, 'r');

    if Caractere = 'P' then fastwriteln('Abre arquivo de hashes');
    ArquivoHashes := FileOpen (NomeArquivoHashes, 'r');

(* Testa se há algum problema com os arquivos. Se há, encerra. *)

    if (ArquivoRegistros in [ctInvalidFileHandle, ctInvalidOpenMode])  then
        CodigoDeErro (true);

    if (ArquivoHashes in [ctInvalidFileHandle, ctInvalidOpenMode])  then
        CodigoDeErro (true);
    
(* Le de um arquivo separado o hash *)
(* Na posicao 0 temos o valor de b, o ModuloDoHash, o máximo de entradas *)
(* e o numero de linhas. *)

    fillchar(vetorbuffer, TamanhoBuffer, byte( ' ' ));
    ResultadoSeek := FileSeek (ArquivoHashes, 0, ctSeekSet, NovaPosicao);
    ResultadoBlockRead := FileBlockRead (ArquivoHashes, vetorbuffer, TamanhoBuffer);
{
    writeln(' ŔesultadoBlockRead: ', ResultadoBlockRead);
    writeln(' NovaPosicao: ', NovaPosicao);

    writeln(' buffer: '); 
    for b := 0 to sizeof(vetorbuffer) do
        write(char(vetorbuffer[b]));
    writeln;
}
(*  Aqui, pegamos os dados do vetor de bytes. *)

    contador := 0;

    BuscaAteAVirgula;
    val(HashEmTexto, b, RetornoDoVal);

    BuscaAteAVirgula;
    val(HashEmTexto, ModuloDoHash, RetornoDoVal);
    
    BuscaAteAVirgula;
    val(HashEmTexto, TotalDeRegistros, RetornoDoVal);
    
    BuscaAteAVirgula;
    val(HashEmTexto, Tamanho, RetornoDoVal);
{
	writeln('b: ',b, ' Modulo: ',ModuloDoHash, ' Tamanho: ',Tamanho,' TotalDeRegistros: ',TotalDeRegistros);
}
    if Caractere = 'S' then
    begin
        temporario := concat('Arquivo com os registros: ', NomeArquivoRegistros);
        fastwriteln(temporario);
        temporario := concat('Arquivo com os hashes: ', NomeArquivoHashes);
        fastwriteln(temporario);
        str(b, HashEmTexto);
        temporario := concat('b: ', HashEmTexto);
        fastwriteln(temporario);
        str(ModuloDoHash, HashEmTexto);
        temporario := concat('Modulo do hash: ', HashEmTexto);
        fastwriteln(temporario);
        str(Tamanho, HashEmTexto);
        temporario := concat('Tamanho: ', HashEmTexto, ' registros.');
        fastwriteln(temporario);
        str(TotalDeRegistros, HashEmTexto);
        temporario := concat('Numero de linhas: ',HashEmTexto);
        fastwriteln(temporario);
    end;
    
    if Caractere = 'P' then
    begin
        str(Tamanho, HashEmTexto);
        temporario := concat('Tamanho: ', HashEmTexto, ' registros.');
        fastwriteln(temporario);
    end;

(* Pede o nome exato de um arquivo a ser procurado *)

    if Caractere = 'P' then
    begin
        temporario := concat('Nome do arquivo: ', pesquisa);
        fastwriteln(temporario);
    end;
        
(* Calcula o hash do nome da pesquisa *)

    hash := CalculaHash(pesquisa);
    
    if Caractere = 'P' then
    begin
        str(hash, HashEmTexto);
        temporario := concat('Hash do nome pesquisado: ', HashEmTexto);
        fastwriteln(temporario);
    end;

(* Le o arquivo de hashes, pegando todos os numeros de hash e salvando num vetor *)

    if Caractere = 'P' then 
        fastwriteln('Le arquivo de hashes');
    LeArquivoDeHashes(hash, Tamanho, TotalDeRegistros);
    
(* Faz a busca binaria no vetor *)

    if Caractere = 'P' then
        fastwriteln('Faz busca.');
    BuscaBinariaNomeDoArquivo(hash, TotalDeRegistros, Posicao, Tentativas);
 
(* Tendo a posicao certa, le o registro e verifica se o nome bate. *)
(*  Ou entao, diz que nao tem aquele nome no arquivo *)

    if Posicao <> 0 then
    begin
        j := Posicao;
        HashTemporario := hash;
        while HashTemporario = hash do
        begin
            j := j - 1;
            HashTemporario := VetorHashes[j];
        end;
{
        writeln(' Existem mais ',(Posicao - j) - 1,' entradas iguais, de ',j + 1,' a ',Posicao,' - acima');
}
        Abaixo := j + 1;
        j := Posicao;
        HashTemporario := hash;
        while HashTemporario = hash do
        begin
            j := j + 1;
            HashTemporario := VetorHashes[j];
        end;
{
        writeln(' Existem mais ',(j - Posicao) - 1,' entradas iguais, de ',Posicao,' a ',j - 1,' - abaixo');
}
        Acima := j - 1;
        
        if Caractere = 'C' then
        begin
            str(((Acima - Abaixo) + 1), HashEmTexto);
            temporario := concat('Numero de entradas encontradas: ', HashEmTexto);
            fastwriteln(temporario);
        end;
                
        if Caractere = 'L' then
            Acima := Abaixo + LimiteDeBuscas;
           
        for j := Abaixo to Acima do
        begin
            LeFichaNoArquivoRegistros (j, Ficha);
{
            writeln('Pesquisa: ', pesquisa, ' Ficha.NomeDoArquivo: ', Ficha.NomeDoArquivo, 
            ' Hash: ', calculahash(Ficha.NomeDoArquivo));
}            
            if CalculaHash(pesquisa) = CalculaHash(Ficha.NomeDoArquivo) then
            begin
                if Caractere = 'P' then
                begin
                    str(j, HashEmTexto);
                    str(Tentativas, TemporarioNumero);
                    temporario := concat('Posicao: ', HashEmTexto,' Tentativas: ', TemporarioNumero,
                    ' Nome do arquivo: ', Ficha.NomeDoArquivo, ' Diretorio: ', Ficha.Diretorio);
                    fastwriteln(temporario);
                end
                else
                    begin
{
                         writeln('-> ', Ficha.Diretorio);
}
                        writeln(Ficha.Diretorio, '\', Ficha.NomeDoArquivo);
                    end;
            end;
        end;
    end
        else
            fastwriteln('Arquivo nao encontrado.');

(* Fecha o arquivo *)
    if Caractere = 'P' then
        fastwriteln('Fecha arquivo.');
    
    if (not FileClose(ArquivoRegistros)) then
        CodigoDeErro(true);
        
    if (not FileClose(ArquivoHashes)) then
        CodigoDeErro(true);

END.
